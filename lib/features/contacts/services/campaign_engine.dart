import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/core/storage/app_storage.dart';
import 'package:untitled3/features/campaigns/data/scheduled_campaign_storage.dart';
import 'package:untitled3/features/campaigns/domain/scheduled_campaign.dart';
import 'package:untitled3/features/contacts/data/campaign_storage.dart';
import 'package:untitled3/features/contacts/data/contact_storage.dart';
import 'package:untitled3/features/contacts/domain/sms_campaign.dart';
import 'package:untitled3/features/settings/domain/server_config.dart';

class CampaignEngine {
  CampaignEngine(this.service);

  final ServiceInstance service;

  SmsCampaign? _active;
  CampaignState _state = CampaignState.queued;
  List<ScheduledCampaign> _scheduled = const [];
  Timer? _schedulerTimer;
  bool _running = false;
  bool _scheduleCheckRunning = false;
  bool _cancelRequested = false;
  bool _stopped = false;

  Future<void> start() async {
    service.on('startCampaign').listen((event) {
      unawaited(_handleStart(event));
    });
    service.on('cancelCampaign').listen((_) {
      _cancelRequested = true;
    });
    service.on('requestCampaignStatus').listen((_) {
      _emitCurrentStatus();
    });
    service.on('reloadScheduledCampaigns').listen((_) {
      unawaited(_reloadSchedules(checkNow: true));
    });
    service.on('deleteScheduledCampaign').listen((event) {
      final id = event?['id']?.toString();
      if (id != null && id.isNotEmpty) unawaited(_deleteScheduled(id));
    });
    service.on('stopService').listen((_) {
      _stopped = true;
      _cancelRequested = true;
      _schedulerTimer?.cancel();
    });

    await _reloadSchedules();
    final saved = await CampaignStorage.loadActive();
    if (saved != null) {
      if (saved.nextIndex >= saved.totalCount) {
        await _finish(saved, CampaignState.completed);
      } else if (!DateTime.now().isBefore(saved.endsAt)) {
        await _finish(saved, CampaignState.windowEnded);
      } else {
        unawaited(_run(saved));
      }
    } else {
      _emitIdle();
    }

    _schedulerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_checkScheduledCampaigns());
    });
    unawaited(_checkScheduledCampaigns());
  }

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

  Future<void> _run(SmsCampaign initial) async {
    if (_running || _stopped) return;
    _running = true;
    _cancelRequested = false;
    var campaign = initial;
    _active = campaign;

    try {
      await SmsBridge.acquireLocks();
      final config = await ConfigStorage.load();
      final simQuery = await SmsBridge.getSimCards();
      final subId = pickSubId(config, simQuery);
      final safeInterval = campaign.totalCount > 1
          ? campaign.intervalSeconds
          : 0;

      while (campaign.nextIndex < campaign.totalCount) {
        if (_stopped && campaign.scheduledCampaignId != null) {
          await _pauseScheduled(campaign);
          return;
        }
        if (_cancelRequested || _stopped) {
          await _finish(campaign, CampaignState.cancelled);
          return;
        }

        final allowedAt = nextAllowedCampaignTime(
          now: DateTime.now(),
          startsAt: campaign.startsAt,
          endsAt: campaign.endsAt,
          dailyStartMinute: campaign.dailyStartMinute,
          dailyEndMinute: campaign.dailyEndMinute,
        );
        if (allowedAt == null) {
          await _finish(campaign, CampaignState.windowEnded);
          return;
        }
        if (allowedAt.isAfter(DateTime.now())) {
          if (_shouldPauseUntilAnotherDay(campaign, allowedAt)) {
            await _pauseScheduled(campaign);
            return;
          }
          _state = CampaignState.waiting;
          await _syncScheduledRuntime(campaign, CampaignState.waiting);
          _emit(campaign, CampaignState.waiting);
          await _waitUntil(allowedAt, campaign.endsAt);
          continue;
        }

        final recipient = campaign.recipients[campaign.nextIndex];
        _state = CampaignState.sending;
        await _syncScheduledRuntime(campaign, CampaignState.sending);
        _emit(campaign, CampaignState.sending, currentContact: recipient.name);

        final result = await SmsBridge.sendSms(
          to: recipient.phone,
          message: campaign.message,
          subId: subId,
        );

        campaign = campaign.copyWith(
          nextIndex: campaign.nextIndex + 1,
          sentCount: campaign.sentCount + (result.ok ? 1 : 0),
          failedCount: campaign.failedCount + (result.ok ? 0 : 1),
          sentRecipientIds: result.ok
              ? [...campaign.sentRecipientIds, recipient.contactId]
              : campaign.sentRecipientIds,
          failedRecipientIds: result.ok
              ? campaign.failedRecipientIds
              : [...campaign.failedRecipientIds, recipient.contactId],
        );
        _active = campaign;
        await CampaignStorage.saveActive(campaign);
        await _syncScheduledRuntime(campaign, CampaignState.sending);
        _emit(
          campaign,
          CampaignState.sending,
          currentContact: recipient.name,
          lastSendSucceeded: result.ok,
        );

        if (campaign.nextIndex >= campaign.totalCount) break;

        final candidate = DateTime.now().add(Duration(seconds: safeInterval));
        final nextSendAt = nextAllowedCampaignTime(
          now: candidate,
          startsAt: campaign.startsAt,
          endsAt: campaign.endsAt,
          dailyStartMinute: campaign.dailyStartMinute,
          dailyEndMinute: campaign.dailyEndMinute,
        );
        if (nextSendAt == null) {
          await _finish(campaign, CampaignState.windowEnded);
          return;
        }
        if (_shouldPauseUntilAnotherDay(campaign, nextSendAt)) {
          await _pauseScheduled(campaign);
          return;
        }
        _state = CampaignState.waiting;
        await _syncScheduledRuntime(campaign, CampaignState.waiting);
        _emit(campaign, CampaignState.waiting);
        await _waitUntil(nextSendAt, campaign.endsAt);
      }

      await _finish(campaign, CampaignState.completed);
    } catch (error) {
      await _finish(campaign, CampaignState.failed, error: error.toString());
    } finally {
      _running = false;
      _cancelRequested = false;
      _active = null;
      if (!_stopped) unawaited(_checkScheduledCampaigns());
    }
  }

  bool _shouldPauseUntilAnotherDay(SmsCampaign campaign, DateTime target) {
    if (campaign.scheduledCampaignId == null) return false;
    final now = DateTime.now();
    return target.year != now.year ||
        target.month != now.month ||
        target.day != now.day;
  }

  Future<void> _pauseScheduled(SmsCampaign campaign) async {
    _state = CampaignState.waiting;
    await _syncScheduledRuntime(campaign, CampaignState.waiting);
    await CampaignStorage.clearActive();
    _active = null;
    _emitIdle();
  }

  Future<void> _waitUntil(DateTime target, DateTime deadline) async {
    while (!_cancelRequested && !_stopped) {
      final now = DateTime.now();
      if (!now.isBefore(target) || !now.isBefore(deadline)) return;
      final remaining = target.difference(now);
      await Future<void>.delayed(
        remaining > const Duration(seconds: 1)
            ? const Duration(seconds: 1)
            : remaining,
      );
    }
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
  }

  Future<void> _reloadSchedules({bool checkNow = false}) async {
    _scheduled = await ScheduledCampaignStorage.load();
    _emitScheduledChanged();
    if (checkNow) unawaited(_checkScheduledCampaigns());
  }

  Future<void> _deleteScheduled(String id) async {
    if (_active?.scheduledCampaignId == id) _cancelRequested = true;
    await ScheduledCampaignStorage.delete(id);
    await _reloadSchedules(checkNow: true);
  }

  Future<void> _checkScheduledCampaigns() async {
    if (_stopped || _scheduleCheckRunning) return;
    _scheduleCheckRunning = true;
    try {
      if (_running || _active != null || _stopped) return;
      _scheduled = await ScheduledCampaignStorage.load();
      final now = DateTime.now();
      for (final campaign in List<ScheduledCampaign>.from(_scheduled)) {
        if (!campaign.isTerminal && !now.isBefore(campaign.endsAt)) {
          await _expireScheduled(campaign);
        }
      }
      _scheduled = await ScheduledCampaignStorage.load();
      final due = _scheduled.where((campaign) {
        if (campaign.isTerminal) return false;
        final allowedAt = campaign.nextAllowedAt(now);
        return allowedAt != null && !allowedAt.isAfter(now);
      }).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      if (due.isEmpty) return;
      await _startScheduled(due.first);
    } finally {
      _scheduleCheckRunning = false;
    }
  }

  Future<void> _startScheduled(ScheduledCampaign schedule) async {
    var runtime = schedule.execution;
    if (runtime == null) {
      final recipients = schedule.audience == CampaignAudience.allAtStart
          ? (await ContactStorage.load())
                .map(CampaignRecipient.fromContact)
                .toList(growable: false)
          : schedule.selectedRecipients;
      runtime = SmsCampaign(
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
    var runtime = schedule.execution;
    if (runtime == null) {
      final recipients = schedule.audience == CampaignAudience.allAtStart
          ? (await ContactStorage.load())
                .map(CampaignRecipient.fromContact)
                .toList(growable: false)
          : schedule.selectedRecipients;
      runtime = SmsCampaign(
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
