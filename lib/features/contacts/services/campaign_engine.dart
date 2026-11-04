import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/core/storage/app_storage.dart';
import 'package:sms_and_call/features/campaigns/data/scheduled_campaign_storage.dart';
import 'package:sms_and_call/features/campaigns/domain/schedule_planner.dart';
import 'package:sms_and_call/features/campaigns/domain/scheduled_campaign.dart';
import 'package:sms_and_call/features/campaigns/services/campaign_runner.dart';
import 'package:sms_and_call/features/contacts/data/campaign_storage.dart';
import 'package:sms_and_call/features/contacts/data/contact_storage.dart';
import 'package:sms_and_call/features/contacts/domain/sms_campaign.dart';
import 'package:sms_and_call/features/optout/optout.dart';
import 'package:sms_and_call/features/settings/domain/send_settings.dart';
import 'package:sms_and_call/features/settings/domain/server_config.dart';
import 'package:sms_and_call/services/lock_coordinator.dart';

/// پوسته‌ی سرویس پس‌زمینه برای کمپین‌ها: رویدادهای رابط کاربری را می‌گیرد، کمپین‌های
/// زمان‌بندی‌شده را سر وقت شروع می‌کند و منطق ارسال را به [CampaignRunner] می‌سپارد.
///
/// قابلیت اتکا از دو لایه می‌آید:
///  1. یک Timer داخل ایزوله (دقتِ ثانیه‌ای وقتی سرویس بیدار است)،
///  2. یک آلارم سیستم‌عامل ([SmsBridge.scheduleWake]) که حتی بعد از کشته‌شدن فرایند
///     یا در حالت Doze، سرویس را دوباره بالا می‌آورد و همین کلاس را راه می‌اندازد.
class CampaignEngine {
  CampaignEngine(this.service);

  final ServiceInstance service;

  SmsCampaign? _active;
  CampaignState _state = CampaignState.queued;
  DateTime? _resumeAt;
  List<ScheduledCampaign> _scheduled = const [];
  Timer? _timer;
  CampaignRunner? _runner;
  SendSettings _settings = const SendSettings();
  SendLedger? _ledger;
  bool _running = false;
  bool _pumping = false;
  bool _stopped = false;
  bool _gatewayEnabled = false;
  String _lastNotice = '';

  static const String _lockName = 'campaign';
  static const Duration _maxTimerSleep = Duration(seconds: 30);

  Future<void> start() async {
    service.on('startCampaign').listen((event) {
      unawaited(_handleStart(event));
    });
    service.on('cancelCampaign').listen((_) {
      _runner?.cancelRequested = true;
      final active = _active;
      if (_runner == null && active != null) {
        // کمپینِ در مکث (بدون اجرای فعال) هم باید لغو شود
        unawaited(_finish(active, CampaignState.cancelled));
      }
    });
    service.on('requestCampaignStatus').listen((_) {
      _emitCurrentStatus();
    });
    service.on('reloadScheduledCampaigns').listen((_) {
      unawaited(_reloadSchedules(pumpNow: true));
    });
    service.on('reloadSendSettings').listen((_) {
      unawaited(_reloadSettings());
    });
    service.on('deleteScheduledCampaign').listen((event) {
      final id = event?['id']?.toString();
      if (id != null && id.isNotEmpty) unawaited(_deleteScheduled(id));
    });
    service.on('updateConfig').listen((event) {
      if (event == null) return;
      try {
        _gatewayEnabled = ServerConfig.fromJson(
          Map<String, dynamic>.from(event),
        ).gatewayEnabled;
      } catch (_) {}
      _publishNotice();
    });
    service.on('stopService').listen((_) {
      _stopped = true;
      _runner?.stopRequested = true;
      _timer?.cancel();
      unawaited(SmsBridge.cancelWake());
    });
    WakeHub.add((_) => unawaited(pump()));

    _gatewayEnabled = (await ConfigStorage.load()).gatewayEnabled;
    await _reloadSettings();
    await _reloadSchedules();

    final saved = await CampaignStorage.loadActive();
    if (saved != null) {
      await _adopt(saved);
    } else {
      _emitIdle();
    }
    await pump();
  }

  Future<void> _reloadSettings() async {
    _settings = await SendSettingsStorage.load();
    final ledger = _ledger ??= await SendLedgerStorage.load();
    ledger.onChanged = (times) => unawaited(SendLedgerStorage.save(times));
  }

  /// کمپین نیمه‌تمامِ ذخیره‌شده (مثلاً بعد از کشته‌شدن برنامه) را برمی‌دارد.
  Future<void> _adopt(SmsCampaign saved) async {
    final scheduleId = saved.scheduledCampaignId;
    if (scheduleId != null) {
      // اگر کاربر کمپین را حذف کرده (و پیام حذف به سرویس نرسیده)، نباید ادامه پیدا کند
      final schedules = await ScheduledCampaignStorage.load();
      final stillThere = schedules.any(
        (item) => item.id == scheduleId && !item.isTerminal,
      );
      if (!stillThere) {
        await CampaignStorage.clearActive();
        return;
      }
    }
    final resolved = saved.resolveInterrupted();
    if (resolved.nextIndex >= resolved.totalCount) {
      await _finish(resolved, CampaignState.completed);
    } else if (!DateTime.now().isBefore(resolved.endsAt)) {
      await _finish(resolved, CampaignState.windowEnded);
    } else {
      _active = resolved;
      _state = CampaignState.waiting;
      _resumeAt = resolved.notBefore;
    }
  }

  // ── Pump: تصمیم‌گیریِ «الان چه کاری باید شروع شود؟» ─────────────────────────

  /// هر بار که چیزی تغییر کرد (تایمر، آلارم، رویداد UI) صدا زده می‌شود.
  Future<void> pump() async {
    if (_stopped || _pumping) return;
    _pumping = true;
    try {
      if (!_running) {
        final active = _active;
        if (active != null) {
          final resumeAt = _resumeAt;
          if (resumeAt == null || !DateTime.now().isBefore(resumeAt)) {
            unawaited(_run(active));
          }
        } else {
          await _checkScheduledCampaigns();
        }
      }
    } catch (_) {
      // یک خطای ورودی/خروجی نباید زمان‌بندی را برای همیشه از کار بیندازد؛ پایین‌تر
      // دوباره تایمر و آلارم ثبت می‌شود و دور بعد تلاش می‌کنیم.
    } finally {
      _pumping = false;
    }
    try {
      await _arm();
    } catch (_) {}
  }

  /// نزدیک‌ترین کار بعدی را هم به Timer داخلی و هم به آلارم سیستم‌عامل می‌دهد.
  Future<void> _arm() async {
    _timer?.cancel();
    _timer = null;
    if (_stopped) return;
    if (_running) return; // خود اجرا تا پایان بیدار می‌ماند و بعدش pump می‌کند

    final now = DateTime.now();
    final plan = planNextWake(
      _scheduled.where((c) => c.id != _active?.scheduledCampaignId),
      now,
    );
    DateTime? at = plan?.at;
    var reason = plan == null ? '' : 'schedule';
    final resume = _active != null ? _resumeAt : null;
    if (resume != null && (at == null || resume.isBefore(at))) {
      at = resume;
      reason = 'resume';
    }

    if (at == null) {
      unawaited(SmsBridge.cancelWake());
      _publishNotice();
      await LockCoordinator.release(_lockName);
      return;
    }

    unawaited(SmsBridge.scheduleWake(at, reason: reason));
    final delay = at.difference(now);
    final sleep = delay <= Duration.zero
        ? const Duration(milliseconds: 250)
        : (delay > _maxTimerSleep ? _maxTimerSleep : delay);
    _timer = Timer(sleep, () => unawaited(pump()));
    _publishNotice(next: at);
    // تا وقتی کاری سررسید نشده، قفل لازم نیست؛ آلارم بیدارمان می‌کند.
    if (delay > const Duration(minutes: 1)) {
      await LockCoordinator.release(_lockName);
    }
  }

  void _publishNotice({DateTime? next}) {
    if (_gatewayEnabled) return; // اعلان را گیت‌وی مدیریت می‌کند
    final s = service;
    if (s is! AndroidServiceInstance) return;
    final text = _running
        ? 'در حال ارسال پیامک‌های کمپین…'
        : next != null
        ? 'کار بعدی: ${_fmtNext(next)}'
        : 'آماده — کمپین فعالی نیست';
    if (text == _lastNotice) return;
    _lastNotice = text;
    s.setForegroundNotificationInfo(title: 'پیامک و تماس', content: text);
  }

  String _fmtNext(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final time = '${two(at.hour)}:${two(at.minute)}';
    return sameDay ? 'امروز $time' : '${at.year}/${two(at.month)}/${two(at.day)} $time';
  }

  // ── شروع ارسال سریع (از تب مخاطب‌ها) ──────────────────────────────────────

  Future<void> _handleStart(Map<String, dynamic>? event) async {
    if (event == null) return;
    if (_running || _active != null) {
      service.invoke('campaignRejected', {
        'message': 'یک ارسال دیگر در حال اجراست.',
      });
      _emitCurrentStatus();
      return;
    }

    try {
      final campaign = SmsCampaign.fromJson(event);
      final validationError = _validate(campaign);
      if (validationError != null) {
        service.invoke('campaignRejected', {'message': validationError});
        return;
      }
      if (campaign.scheduledCampaignId == null) {
        final schedules = await ScheduledCampaignStorage.load();
        final conflict = schedules.any(
          (item) => scheduledCampaignOverlapsRange(
            item,
            campaign.startsAt,
            campaign.endsAt,
          ),
        );
        if (conflict) {
          service.invoke('campaignRejected', {
            'message':
                'این بازه با یک کمپین زمان‌بندی‌شده تداخل دارد. بازه دیگری انتخاب کنید.',
          });
          return;
        }
      }
      await CampaignStorage.saveActive(campaign);
      _active = campaign;
      _state = CampaignState.queued;
      _resumeAt = null;
      _emit(campaign, CampaignState.queued);
      unawaited(_run(campaign));
    } catch (error) {
      service.invoke('campaignRejected', {
        'message': 'اطلاعات ارسال قابل خواندن نیست: $error',
      });
    }
  }

  String? _validate(SmsCampaign campaign) {
    if (campaign.id.isEmpty || campaign.message.trim().isEmpty) {
      return 'متن پیام یا شناسه ارسال خالی است.';
    }
    if (campaign.recipients.isEmpty) {
      return 'هیچ مخاطبی برای ارسال انتخاب نشده است.';
    }
    if (campaign.recipients.length > 1 && campaign.intervalSeconds <= 0) {
      return 'فاصله بین پیام‌ها باید بیشتر از صفر باشد.';
    }
    if (!campaign.endsAt.isAfter(campaign.startsAt)) {
      return 'پایان بازه باید بعد از زمان شروع باشد.';
    }
    if (!DateTime.now().isBefore(campaign.endsAt)) {
      return 'بازه زمانی این ارسال پایان یافته است.';
    }
    final dailyStart = campaign.dailyStartMinute;
    final dailyEnd = campaign.dailyEndMinute;
    if ((dailyStart == null) != (dailyEnd == null) ||
        dailyStart != null &&
            (dailyStart < 0 || dailyEnd! > 24 * 60 || dailyEnd <= dailyStart)) {
      return 'ساعت روزانه کمپین معتبر نیست.';
    }
    return null;
  }

  // ── اجرا ─────────────────────────────────────────────────────────────────

  Future<void> _run(SmsCampaign initial) async {
    if (_running || _stopped) return;
    _running = true;
    _resumeAt = null;
    _timer?.cancel();
    var latest = initial;
    _active = initial;

    final runner = CampaignRunner(
      send: SmsBridge.sendSms,
      onProgress: (campaign, state, {currentContact, lastSendSucceeded, note}) async {
        latest = campaign;
        _active = campaign;
        _state = state;
        await CampaignStorage.saveActive(campaign);
        await _syncScheduledRuntime(campaign, state);
        _emit(
          campaign,
          state,
          currentContact: currentContact,
          lastSendSucceeded: lastSendSucceeded,
        );
      },
      loadOptOutKeys: OptOutStorage.loadKeys,
      settings: () => _settings,
      ledger: _ledger ?? SendLedger(),
      resolveSubId: _resolveSubId,
    );
    _runner = runner;

    try {
      await LockCoordinator.acquire(_lockName);
      _publishNotice();
      await _reloadSettings();
      final result = await runner.run(initial);
      latest = result.campaign;
      await _handleResult(result);
    } catch (error) {
      await _finish(latest, CampaignState.failed, error: error.toString());
    } finally {
      _running = false;
      _runner = null;
      if (_active == null) await LockCoordinator.release(_lockName);
      if (!_stopped) unawaited(pump());
    }
  }

  Future<int> _resolveSubId() async {
    final config = await ConfigStorage.load();
    final query = await SmsBridge.getSimCards();
    return pickSubId(config, query);
  }

  Future<void> _handleResult(RunResult result) async {
    final campaign = result.campaign;
    switch (result.status) {
      case RunStatus.completed:
        await _finish(campaign, CampaignState.completed);
      case RunStatus.cancelled:
        await _finish(campaign, CampaignState.cancelled);
      case RunStatus.windowEnded:
        await _finish(campaign, CampaignState.windowEnded);
      case RunStatus.failed:
        await _finish(campaign, CampaignState.failed, error: result.error);
      case RunStatus.paused:
        if (_stopped && campaign.scheduledCampaignId == null) {
          // توقف دستی سرویس، ارسال سریع را لغو می‌کند (مثل قبل)
          await _finish(campaign, CampaignState.cancelled);
        } else if (campaign.scheduledCampaignId != null) {
          await _pauseScheduled(campaign);
        } else {
          _active = campaign;
          _state = CampaignState.waiting;
          _resumeAt = result.resumeAt;
          await CampaignStorage.saveActive(campaign);
          _emit(campaign, CampaignState.waiting);
        }
    }
  }

  Future<void> _pauseScheduled(SmsCampaign campaign) async {
    _state = CampaignState.waiting;
    await _syncScheduledRuntime(campaign, CampaignState.waiting);
    await CampaignStorage.clearActive();
    _active = null;
    _resumeAt = null;
    _emitIdle();
  }

  Future<void> _finish(
    SmsCampaign campaign,
    CampaignState state, {
    String? error,
  }) async {
    _active = campaign;
    _state = state;
    await CampaignStorage.addHistory(
      CampaignHistory.fromCampaign(campaign, state),
    );
    await _syncScheduledRuntime(campaign, state, error: error);
    await CampaignStorage.clearActive();
    _emit(campaign, state, error: error);
    _active = null;
    _resumeAt = null;
  }

  // ── کمپین‌های زمان‌بندی‌شده ───────────────────────────────────────────────

  Future<void> _reloadSchedules({bool pumpNow = false}) async {
    _scheduled = await ScheduledCampaignStorage.load();
    _emitScheduledChanged();
    if (pumpNow) unawaited(pump());
  }

  Future<void> _deleteScheduled(String id) async {
    if (_active?.scheduledCampaignId == id) {
      _runner?.cancelRequested = true;
      if (_runner == null) {
        _active = null;
        _resumeAt = null;
        await CampaignStorage.clearActive();
        _emitIdle();
      }
    }
    await ScheduledCampaignStorage.delete(id);
    await _reloadSchedules(pumpNow: true);
  }

  Future<void> _checkScheduledCampaigns() async {
    _scheduled = await ScheduledCampaignStorage.load();
    final now = DateTime.now();
    for (final campaign in expiredCampaigns(_scheduled, now)) {
      await _expireScheduled(campaign);
    }
    _scheduled = await ScheduledCampaignStorage.load();
    final due = dueCampaigns(_scheduled, now);
    if (due.isEmpty) return;
    await _startScheduled(due.first);
  }

  Future<SmsCampaign> _runtimeFor(ScheduledCampaign schedule) async {
    final existing = schedule.execution;
    if (existing != null) {
      // ساعت دیواری از تعریف کمپین دوباره ساخته می‌شود تا با تغییر منطقه‌ی زمانی جابه‌جا نشود
      return existing.copyWith(
        startsAt: schedule.startsAt,
        endsAt: schedule.endsAt,
      );
    }
    final recipients = schedule.audience == CampaignAudience.allAtStart
        ? (await ContactStorage.load())
              .map(CampaignRecipient.fromContact)
              .toList(growable: false)
        : schedule.selectedRecipients;
    return SmsCampaign(
      id: schedule.id,
      title: schedule.title,
      scheduledCampaignId: schedule.id,
      message: schedule.message,
      recipients: recipients,
      intervalSeconds: schedule.intervalSeconds,
      startsAt: schedule.startsAt,
      endsAt: schedule.endsAt,
      dailyStartMinute: schedule.dailyStartMinute,
      dailyEndMinute: schedule.dailyEndMinute,
    );
  }

  Future<void> _startScheduled(ScheduledCampaign schedule) async {
    final runtime = await _runtimeFor(schedule);

    if (runtime.recipients.isEmpty) {
      await _finishScheduledWithoutRecipients(schedule, runtime);
      return;
    }
    if (runtime.nextIndex >= runtime.totalCount) {
      await _finish(runtime, CampaignState.completed);
      return;
    }

    await CampaignStorage.saveActive(runtime);
    _active = runtime;
    _state = CampaignState.queued;
    _resumeAt = null;
    await _syncScheduledRuntime(runtime, CampaignState.queued);
    _emit(runtime, CampaignState.queued);
    unawaited(_run(runtime));
  }

  Future<void> _finishScheduledWithoutRecipients(
    ScheduledCampaign schedule,
    SmsCampaign runtime,
  ) async {
    const message = 'در زمان شروع کمپین هیچ مخاطبی برای ارسال وجود نداشت.';
    await CampaignStorage.addHistory(
      CampaignHistory.fromCampaign(runtime, CampaignState.failed),
    );
    await ScheduledCampaignStorage.update(
      schedule.id,
      (current) => current.copyWith(
        state: ScheduledCampaignState.failed,
        execution: runtime,
        lastError: message,
      ),
    );
    await _reloadSchedules();
  }

  Future<void> _expireScheduled(ScheduledCampaign schedule) async {
    final runtime = await _runtimeFor(schedule);
    await CampaignStorage.addHistory(
      CampaignHistory.fromCampaign(runtime, CampaignState.windowEnded),
    );
    await ScheduledCampaignStorage.update(
      schedule.id,
      (current) => current.copyWith(
        state: ScheduledCampaignState.windowEnded,
        execution: runtime,
      ),
    );
    _scheduled = await ScheduledCampaignStorage.load();
    _emitScheduledChanged();
  }

  Future<void> _syncScheduledRuntime(
    SmsCampaign campaign,
    CampaignState runtimeState, {
    String? error,
  }) async {
    final scheduleId = campaign.scheduledCampaignId;
    if (scheduleId == null || scheduleId.isEmpty) return;
    final state = switch (runtimeState) {
      CampaignState.completed => ScheduledCampaignState.completed,
      CampaignState.cancelled => ScheduledCampaignState.cancelled,
      CampaignState.windowEnded => ScheduledCampaignState.windowEnded,
      CampaignState.failed => ScheduledCampaignState.failed,
      CampaignState.sending => ScheduledCampaignState.sending,
      _ => ScheduledCampaignState.waiting,
    };
    await ScheduledCampaignStorage.update(
      scheduleId,
      (current) => current.copyWith(
        state: state,
        execution: campaign,
        lastError: error,
        clearLastError: error == null,
      ),
    );
    _scheduled = await ScheduledCampaignStorage.load();
    _emitScheduledChanged();
  }

  // ── رویدادها به رابط کاربری ──────────────────────────────────────────────

  void _emitCurrentStatus() {
    final active = _active;
    if (active == null) {
      _emitIdle();
    } else {
      _emit(active, _state);
    }
  }

  void _emitIdle() {
    service.invoke('campaignStatus', {'state': 'idle'});
  }

  void _emitScheduledChanged() {
    service.invoke('scheduledCampaignsChanged', {
      'count': _scheduled.length,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _emit(
    SmsCampaign campaign,
    CampaignState state, {
    String? currentContact,
    bool? lastSendSucceeded,
    String? error,
  }) {
    service.invoke('campaignStatus', {
      'state': state.name,
      'campaign': campaign.toJson(),
      if (currentContact != null) 'currentContact': currentContact,
      if (lastSendSucceeded != null) 'lastSendSucceeded': lastSendSucceeded,
      if (error != null) 'error': error,
    });
  }
}
