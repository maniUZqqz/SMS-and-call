import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;
import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/core/constants/app_constants.dart';
import 'package:untitled3/core/errors/error_classifier.dart';
import 'package:untitled3/core/storage/app_storage.dart';
import 'package:untitled3/features/logs/data/log_storage.dart';
import 'package:untitled3/features/logs/domain/log_entry.dart';
import 'package:untitled3/features/settings/domain/server_config.dart';

class _Flow {
  _Flow(this.entry);
  final LogEntry entry;
  int smsAttempts = 0;
  int markAttempts = 0;
  bool delivered = false;
  DateTime? retryAt;

  FlowStep get receive => entry.steps[0];
  FlowStep get sms => entry.steps[1];
  FlowStep get mark => entry.steps[2];
}

class GatewayEngine {
  GatewayEngine(this.service);

  final ServiceInstance service;

  final List<LogEntry> _logs = <LogEntry>[];
  final Set<String> _sentIds = <String>{};
  final Map<String, _Flow> _flows = <String, _Flow>{};

  ServerConfig _config = ServerConfig.defaults();
  List<SimCard> _sims = <SimCard>[];
  bool _stopped = false;
  String _conn = 'init';
  int _consecutive = 0;
  int _polls = 0;
  int _sent = 0;
  int _failed = 0;
  int? _latency;
  DateTime? _lastOk;
  bool _idleLogged = false;
  String _lastNotif = '';

  Future<void> start() async {
    service.on('stopService').listen((_) => _shutdown());
    service.on('updateConfig').listen(_onConfigUpdate);
    service.on('requestStatus').listen((_) => _emitStatus());
    service.on('clearLogs').listen((_) {
      _logs.clear();
      _flows.clear();
    });

    // جلوگیری از خوابیدن CPU/Wi-Fi وقتی برنامه بسته است
    unawaited(SmsBridge.acquireLocks());

    _config = await ConfigStorage.load();

    final history = await LogStorage.load();
    final changed = LogStorage.closeStale(history);
    _logs.addAll(history);
    for (final e in changed) {
      service.invoke('update', {'entry': e.toJson()});
    }

    _add(
      LogEntry(
        kind: LogKind.system,
        level: LogLevel.success,
        title: 'سرویس شروع شد',
        meta: {
          'سرور': _config.baseUrl,
          'دریافت کد': _config.otpPath,
          'ثبت ارسال': _config.markSentPath,
          'سیم‌کارت': _config.simTitle,
          'بازه بررسی': 'هر ۲ ثانیه',
        },
      ),
    );
    _emitStatus();
    unawaited(_logEnvironment());
    unawaited(_loop());
  }

  Future<void> _logEnvironment() async {
    try {
      final st = await SmsBridge.status();
      if (!st.available) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.error,
            title: 'افزونه بومی پیامک در سرویس در دسترس نیست',
            hint: 'پروژه را flutter clean کنید و دوباره build بگیرید.',
            dedupeKey: 'env-plugin',
          ),
        );
        return;
      }
      if (!st.telephony) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.error,
            title: 'این دستگاه قابلیت پیامک ندارد',
            hint: 'برنامه را روی گوشی دارای سیم‌کارت اجرا کنید.',
            dedupeKey: 'env-telephony',
          ),
        );
      }
      if (!st.sendSms) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.error,
            title: 'مجوز ارسال پیامک داده نشده',
            hint: 'برنامه را باز کنید و از «بررسی مجوزها» آن را فعال کنید.',
            dedupeKey: 'env-sms',
          ),
        );
      }
      if (st.airplane) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.warning,
            title: 'حالت پرواز روشن است',
            hint: 'تا حالت پرواز روشن است پیامکی ارسال نمی‌شود.',
            dedupeKey: 'env-airplane',
          ),
        );
      }

      final q = await SmsBridge.getSimCards();
      if (!q.permissionGranted) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.warning,
            title: 'دسترسی به لیست سیم‌کارت‌ها داده نشده',
            hint:
                'بدون مجوز «تلفن» انتخاب سیم‌کارت ممکن نیست و از پیش‌فرض گوشی استفاده می‌شود.',
            dedupeKey: 'env-phone',
          ),
        );
        return;
      }
      _sims = q.sims;
      final meta = <String, String>{'تعداد فعال': '${q.sims.length}'};
      for (final s in q.sims) {
        meta[s.slotLabel] =
            '${s.carrier.isNotEmpty ? s.carrier : s.name}${s.number.isNotEmpty ? ' · ${s.number}' : ''}'
            '${s.subscriptionId == q.defaultSmsSubId ? ' (پیش‌فرض پیامک)' : ''}';
      }
      meta['سیم انتخابی'] = _config.simTitle;
      _add(
        LogEntry(
          kind: LogKind.system,
          level: q.sims.isEmpty ? LogLevel.warning : LogLevel.info,
          title: q.sims.isEmpty
              ? 'سیم‌کارت فعالی پیدا نشد'
              : 'وضعیت سیم‌کارت‌ها',
          meta: meta,
        ),
      );
    } catch (_) {}
  }

  LogEntry _add(LogEntry e) {
    if (e.dedupeKey != null &&
        _logs.isNotEmpty &&
        _logs.first.dedupeKey == e.dedupeKey) {
      final top = _logs.first;
      top.count++;
      top.time = DateTime.now();
      top.detail = e.detail;
      top.hint = e.hint;
      top.tech = e.tech;
      top.meta = e.meta;
      _emit(top);
      return top;
    }

    _logs.insert(0, e);

    if (_logs.length > kMaxLogs) {
      _logs.removeRange(kMaxLogs, _logs.length);
    }

    _emit(e);
    return e;
  }

  void _touch(LogEntry e) {
    e.time = DateTime.now();
    _emit(e);
  }

  void _emit(LogEntry e) {
    service.invoke('update', {'entry': e.toJson()});
    LogStorage.save(_logs);
    _notify(e);
  }

  void _notify(LogEntry e) {
    final text = e.notificationText;
    final s = service;

    if (s is AndroidServiceInstance && text != _lastNotif) {
      _lastNotif = text;
      s.setForegroundNotificationInfo(title: 'گیت‌وی پیامک', content: text);
    }
  }

  void _emitStatus() {
    service.invoke('status', {
      'conn': _conn,
      'latency': _latency,
      'polls': _polls,
      'sent': _sent,
      'failed': _failed,
      'failures': _consecutive,
      'lastOk': _lastOk?.millisecondsSinceEpoch,
    });
  }

  int get _nextDelaySecs =>
      _consecutive == 0 ? 2 : min(2 + _consecutive * 2, 10);

  String _host(Uri u) => u.hasPort ? '${u.host}:${u.port}' : u.host;

  String _snippet(List<int> bytes, [int max = 240]) {
    final s = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (s.isEmpty) return '(بدنه خالی)';
    return s.length > max ? '${s.substring(0, max)}…' : s;
  }

  void _onConfigUpdate(Map<String, dynamic>? event) {
    if (event == null) return;

    try {
      final old = _config;

      _config = ServerConfig.fromJson(Map<String, dynamic>.from(event));

      final serverChanged =
          old.baseUrl != _config.baseUrl ||
          old.otpPath != _config.otpPath ||
          old.markSentPath != _config.markSentPath;
      final smsChanged =
          old.smsTemplate != _config.smsTemplate ||
          old.simSubscriptionId != _config.simSubscriptionId;

      if (serverChanged) {
        _conn = 'init';
        _consecutive = 0;
        _idleLogged = false;

        _add(
          LogEntry(
            kind: LogKind.system,
            title: 'تنظیمات سرور به‌روز شد',
            meta: {
              'سرور قبلی': old.baseUrl,
              'سرور جدید': _config.baseUrl,
              'دریافت کد': _config.otpPath,
              'ثبت ارسال': _config.markSentPath,
            },
          ),
        );
      }

      if (smsChanged) {
        // پیامک‌هایی که قبلاً شکست خورده‌اند بلافاصله با تنظیمات جدید دوباره امتحان شوند
        for (final f in _flows.values) {
          f.retryAt = null;
        }
        _add(
          LogEntry(
            kind: LogKind.system,
            title: 'تنظیمات پیامک به‌روز شد',
            meta: {
              'سیم‌کارت': _config.simTitle,
              'نمونه پیامک': _config.previewMessage,
            },
          ),
        );
      }
    } catch (e) {
      _add(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.error,
          title: 'اعمال تنظیمات جدید ناموفق بود',
          tech: ErrorClassifier.describe(e),
        ),
      );
    }
  }

  Future<void> _shutdown() async {
    _stopped = true;

    _add(
      LogEntry(
        kind: LogKind.system,
        level: LogLevel.warning,
        title: 'سرویس متوقف شد',
        meta: {
          'تعداد بررسی': '$_polls',
          'پیامک ارسال‌شده': '$_sent',
          'خطاها': '$_failed',
        },
      ),
    );

    await LogStorage.flush(_logs);
    await SmsBridge.releaseLocks();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    service.stopSelf();
  }

  Future<void> _loop() async {
    while (!_stopped) {
      try {
        await _pollOnce();
      } catch (e) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.error,
            title: 'خطای غیرمنتظره در سرویس',
            hint: 'اگر تکرار شد، گزارش را کپی و بررسی کنید.',
            tech: ErrorClassifier.describe(e),
            dedupeKey: 'unexpected:${e.runtimeType}',
          ),
        );
      }

      if (_stopped) break;

      _emitStatus();

      await Future<void>.delayed(Duration(seconds: _nextDelaySecs));
    }
  }

  Future<void> _pollOnce() async {
    _polls++;

    final uri = _config.otpUri;
    final sw = Stopwatch()..start();

    http.Response res;

    try {
      res = await http.get(uri).timeout(const Duration(seconds: 8));
    } catch (e) {
      sw.stop();
      _onConnectionFailure(e, uri, sw.elapsedMilliseconds);
      return;
    }

    sw.stop();

    final ms = sw.elapsedMilliseconds;
    _latency = ms;

    if (res.statusCode != 200) {
      _onHttpError(res, uri, ms);
      return;
    }

    List<dynamic> items;

    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));

      if (decoded is! List) {
        throw const FormatException('پاسخ سرور باید یک لیست JSON باشد');
      }

      items = decoded;
    } catch (e) {
      _onBadPayload(e, res, uri, ms);
      return;
    }

    final recovered = _onConnected(uri, ms);

    if (items.isEmpty) {
      if (!_idleLogged) {
        if (!recovered) {
          _add(
            LogEntry(
              kind: LogKind.response,
              title: 'صف سرور خالی است — منتظر شماره جدید',
              meta: {
                'سرور': _host(uri),
                'درخواست': 'GET $uri',
                'وضعیت': '200 OK',
                'زمان': '${ms}ms',
              },
              dedupeKey: 'idle',
            ),
          );
        }

        _idleLogged = true;
      }
    } else {
      _idleLogged = false;
    }

    final currentIds = <String>{};

    for (final raw in items) {
      if (raw is Map && raw['id'] != null) {
        currentIds.add(raw['id'].toString());
      }
    }

    for (final raw in items) {
      if (_stopped) return;

      await _processItem(raw, uri, ms);
    }

    for (final entry in _flows.entries.toList()) {
      if (currentIds.contains(entry.key)) continue;

      final f = entry.value;
      var changed = false;

      for (final s in f.entry.steps) {
        if (s.state == StepState.pending || s.state == StepState.fail) {
          s.update(
            StepState.warn,
            detail: '${s.detail ?? s.label} · سپس از صف سرور حذف شد',
          );
          changed = true;
        }
      }

      _flows.remove(entry.key);

      if (changed) {
        _touch(f.entry);
      }
    }
  }

  bool _onConnected(Uri uri, int ms) {
    final was = _conn;

    _lastOk = DateTime.now();

    if (was == 'ok') {
      _consecutive = 0;
      return false;
    }

    final tries = _consecutive;

    _consecutive = 0;
    _conn = 'ok';

    _add(
      LogEntry(
        kind: LogKind.response,
        level: LogLevel.success,
        title: was == 'init'
            ? 'اتصال به سرور برقرار شد'
            : 'ارتباط با سرور دوباره برقرار شد',
        detail: tries > 0 ? 'پس از $tries تلاش ناموفق' : null,
        meta: {
          'سرور': _host(uri),
          'درخواست': 'GET $uri',
          'وضعیت': '200 OK',
          'زمان': '${ms}ms',
        },
      ),
    );

    return true;
  }

  void _onConnectionFailure(Object e, Uri uri, int ms) {
    _consecutive++;

    if (_conn != 'down') {
      _failed++;
    }

    _conn = 'down';
    _idleLogged = false;

    final info = ErrorClassifier.network(e);

    _add(
      LogEntry(
        kind: LogKind.request,
        level: LogLevel.error,
        title: info.title,
        hint: info.hint,
        tech: info.technical,
        dedupeKey: 'conn:${info.title}',
        meta: {
          'سرور': _host(uri),
          'درخواست': 'GET $uri',
          'پاسخ': 'دریافت نشد',
          'زمان سپری‌شده': '${ms}ms',
          'تلاش متوالی': '$_consecutive',
          'تلاش بعدی': '$_nextDelaySecs ثانیه دیگر',
        },
      ),
    );
  }

  void _onHttpError(http.Response res, Uri uri, int ms) {
    _consecutive++;

    if (_conn != 'error') {
      _failed++;
    }

    _conn = 'error';
    _idleLogged = false;

    final info = ErrorClassifier.httpStatus(res.statusCode);

    _add(
      LogEntry(
        kind: LogKind.response,
        level: LogLevel.error,
        title: info.title,
        detail: 'سرور پاسخ ${res.statusCode} ${res.reasonPhrase ?? ''} برگرداند'
            .trim(),
        hint: info.hint,
        tech:
            'GET $uri\n${res.statusCode} ${res.reasonPhrase ?? ''}\n${_snippet(res.bodyBytes)}',
        dedupeKey: 'http:${res.statusCode}',
        meta: {
          'سرور': _host(uri),
          'درخواست': 'GET $uri',
          'وضعیت': '${res.statusCode}',
          'زمان': '${ms}ms',
          'تلاش متوالی': '$_consecutive',
          'تلاش بعدی': '$_nextDelaySecs ثانیه دیگر',
        },
      ),
    );
  }

  void _onBadPayload(Object e, http.Response res, Uri uri, int ms) {
    _consecutive++;

    if (_conn != 'error') {
      _failed++;
    }

    _conn = 'error';
    _idleLogged = false;

    _add(
      LogEntry(
        kind: LogKind.response,
        level: LogLevel.error,
        title: 'پاسخ سرور قابل خواندن نیست',
        hint:
            'مسیر دریافت کد درست است؟ سرور باید لیست JSON شامل id، phone و code برگرداند.',
        tech:
            'GET $uri\n200 · ${ms}ms\n${_snippet(res.bodyBytes)}\n${ErrorClassifier.describe(e)}',
        dedupeKey: 'payload',
        meta: {
          'سرور': _host(uri),
          'درخواست': 'GET $uri',
          'وضعیت': '200 (قالب نامعتبر)',
          'تلاش بعدی': '$_nextDelaySecs ثانیه دیگر',
        },
      ),
    );
  }

  // ── per-item pipeline ──────────────────────────────────────────────────────

  void _badItem(String raw) {
    _add(
      LogEntry(
        kind: LogKind.response,
        level: LogLevel.error,
        title: 'آیتم ناقص از سرور دریافت شد',
        hint: 'هر آیتم باید شامل id، phone و code باشد.',
        tech: raw.length > 300 ? '${raw.substring(0, 300)}…' : raw,
        dedupeKey: 'bad-item',
      ),
    );
  }

  Future<void> _processItem(dynamic raw, Uri pollUri, int pollMs) async {
    final Map<String, dynamic> item;

    try {
      item = Map<String, dynamic>.from(raw as Map);
    } catch (_) {
      _badItem(raw.toString());
      return;
    }

    final id = item['id']?.toString();
    final phone = item['phone']?.toString().trim();
    final code = item['code']?.toString().trim();

    if (id == null ||
        id.isEmpty ||
        phone == null ||
        phone.isEmpty ||
        code == null ||
        code.isEmpty) {
      _badItem(jsonEncode(item));
      return;
    }

    var flow = _flows[id];

    if (flow == null) {
      flow = _Flow(
        LogEntry(
          kind: LogKind.flow,
          title: 'کد تایید برای $phone',
          meta: {
            'شناسه': id,
            'شماره': phone,
            'کد': '•' * code.length,
            'سیم‌کارت': _config.simTitle,
            'سرور': _host(pollUri),
          },
          steps: [
            FlowStep(
              'دریافت از سرور',
              state: StepState.ok,
              detail: 'پاسخ 200 در ${pollMs}ms',
              tech: 'GET $pollUri',
            ),
            FlowStep('ارسال پیامک'),
            FlowStep('ثبت در سرور'),
          ],
        ),
      );

      _flows[id] = flow;
      _add(flow.entry);
    }

    if (!_sentIds.contains(id)) {
      final at = flow.retryAt;

      if (at != null && DateTime.now().isBefore(at)) {
        return;
      }

      await _sendSms(flow, id, phone, code);

      if (!_sentIds.contains(id)) {
        return;
      }
    } else if (flow.sms.state == StepState.pending) {
      flow.sms.update(
        StepState.warn,
        detail: 'قبلاً ارسال شده بود؛ پیامک تکراری فرستاده نشد',
      );

      _touch(flow.entry);
    }

    await _markSent(flow, id);
  }

  /// subId نهایی را تعیین می‌کند و در صورت لزوم (تغییر شناسه‌ی سیم / نبودن پیش‌فرض) لاگ می‌گذارد.
  Future<int> _resolveSubId() async {
    final q = await SmsBridge.getSimCards();
    if (q.permissionGranted) _sims = q.sims;

    final picked = pickSubId(_config, q);

    if (q.permissionGranted) {
      final want = _config.simSubscriptionId;

      if (want >= 0 && picked != want && picked >= 0) {
        final s = q.sims.firstWhere(
          (x) => x.subscriptionId == picked,
          orElse: () => q.sims.first,
        );
        _config = _config.copyWith(
          simSubscriptionId: picked,
          simSlot: s.slot,
          simLabel: s.title,
        );
        unawaited(ConfigStorage.save(_config));
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.warning,
            title: 'شناسه‌ی سیم‌کارت تغییر کرده بود؛ به‌روز شد',
            detail: 'سیم‌کارت اسلات ${s.slot + 1} با شناسه‌ی جدید انتخاب شد.',
            dedupeKey: 'sim-remap',
          ),
        );
      } else if (want < 0 && q.defaultSmsSubId < 0 && picked >= 0) {
        _add(
          LogEntry(
            kind: LogKind.system,
            level: LogLevel.info,
            title:
                'سیم‌کارت پیش‌فرض پیامک در گوشی تعیین نشده؛ از ${simNameOf(q.sims, picked)} استفاده شد',
            hint:
                'برای ثبات بیشتر یک سیم‌کارت را در «تنظیمات پیامک» برنامه انتخاب کنید.',
            dedupeKey: 'sim-auto',
          ),
        );
      }
    }

    return picked;
  }

  Future<void> _sendSms(
    _Flow flow,
    String id,
    String phone,
    String code,
  ) async {
    final step = flow.sms;

    flow.smsAttempts++;
    final attempt = flow.smsAttempts;

    if (step.state == StepState.pending) {
      step.update(StepState.pending, detail: 'در حال ارسال…');

      _touch(flow.entry);
    }

    if (RegExp(r'\d').allMatches(phone).length < 5) {
      _smsFailed(
        flow,
        step,
        'شماره نامعتبر است',
        'فرمت شماره گیرنده را در سرور بررسی کنید.',
        'phone="$phone"',
        permanent: true,
      );
      return;
    }

    try {
      final subId = await _resolveSubId();
      final message = _config.buildMessage(code);

      final r = await SmsBridge.sendSms(
        to: phone,
        message: message,
        subId: subId,
      );

      if (r.ok) {
        _sentIds.add(id);

        if (_sentIds.length > 500) {
          _sentIds.remove(_sentIds.first);
        }

        _sent++;
        flow.retryAt = null;

        final simName = simNameOf(_sims, r.usedSubId);

        step.update(
          StepState.ok,
          detail:
              'از $simName ارسال شد${r.parts > 1 ? ' (${r.parts} بخش)' : ''}',
          tech:
              'subId=${r.usedSubId} · parts=${r.partsOk}/${r.parts}'
              '${attempt > 1 ? ' · موفق در تلاش $attempt' : ''}',
        );

        // اگر نام سیم در لاگ اصلی هم نمایش داده شود، ردیابی راحت‌تر است
        flow.entry.meta['سیم‌کارت'] = simName;

        _touch(flow.entry);
      } else {
        final info = ErrorClassifier.smsResult(r);

        _smsFailed(
          flow,
          step,
          info.title,
          info.hint,
          info.technical,
          permanent: info.permanent,
        );
      }
    } catch (e) {
      final info = ErrorClassifier.sms(e);

      _smsFailed(
        flow,
        step,
        info.title,
        info.hint,
        info.technical,
        permanent: info.permanent,
      );
    }
  }

  void _smsFailed(
    _Flow flow,
    FlowStep step,
    String title,
    String hint,
    String tech, {
    bool permanent = false,
  }) {
    final wait = permanent
        ? 60
        : min(60, 2 * (1 << min(flow.smsAttempts - 1, 5)));

    flow.retryAt = DateTime.now().add(Duration(seconds: wait));

    if (step.state != StepState.fail) {
      _failed++;
    }

    step.update(
      StepState.fail,
      detail: '$title · تلاش ${flow.smsAttempts}',
      hint: '$hint\nتلاش بعدی حدود $wait ثانیه دیگر',
      tech: tech,
    );

    _touch(flow.entry);
  }

  Future<void> _markSent(_Flow flow, String id) async {
    final step = flow.mark;

    flow.markAttempts++;

    final uri = _config.markSentUri;
    final body = jsonEncode({'id': id});
    final req = 'POST $uri\n$body';

    if (step.state == StepState.pending) {
      step.update(StepState.pending, detail: 'در حال ثبت در سرور…');

      _touch(flow.entry);
    }

    final sw = Stopwatch()..start();

    try {
      final res = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 8));

      sw.stop();

      final reply =
          '${res.statusCode} ${res.reasonPhrase ?? ''} · ${sw.elapsedMilliseconds}ms'
              .trim();

      if (res.statusCode == 200) {
        step.update(StepState.ok, detail: 'سرور تایید کرد ($reply)', tech: req);

        _finishFlow(id, flow);
      } else if (res.statusCode == 404) {
        step.update(
          StepState.warn,
          detail: 'سرور این شناسه را نمی‌شناسد (404) — احتمالاً قبلاً ثبت شده',
          tech: req,
        );

        _finishFlow(id, flow);
      } else {
        final info = ErrorClassifier.httpStatus(res.statusCode);

        _markFailed(
          flow,
          step,
          info.title,
          info.hint,
          '$req\nپاسخ: $reply\n${_snippet(res.bodyBytes)}',
        );
      }
    } catch (e) {
      sw.stop();

      final info = ErrorClassifier.network(e);

      _markFailed(flow, step, info.title, info.hint, '$req\n${info.technical}');
    }
  }

  void _markFailed(
    _Flow flow,
    FlowStep step,
    String title,
    String hint,
    String tech,
  ) {
    if (step.state != StepState.fail) {
      _failed++;
    }

    step.update(
      StepState.fail,
      detail: '$title · تلاش ${flow.markAttempts}',
      hint: '$hint\nپیامک ارسال شده؛ ثبت در بررسی بعدی خودکار تکرار می‌شود.',
      tech: tech,
    );

    _touch(flow.entry);
  }

  void _finishFlow(String id, _Flow flow) {
    flow.retryAt = null;
    _flows.remove(id);
    _touch(flow.entry);
  }
}
