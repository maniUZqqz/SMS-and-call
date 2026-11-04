import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/features/calls/services/call_cycle.dart';
import 'package:sms_and_call/services/lock_coordinator.dart';

/// بخش «تماس» سرویس پس‌زمینه: بدون هیچ دخالت کاربر ضبط‌های تازه را پیدا می‌کند،
/// به تماس وصل می‌کند و به متن تبدیل می‌کند.
///
/// محرک‌ها:
///  - شروع سرویس،
///  - آلارم `call_ended` (چند ثانیه بعد از پایان هر تماس؛ توسط گیرنده‌ی بومی PHONE_STATE)،
///  - آلارم `calls` (تلاش دوباره‌ی ضبطی که تبدیلش خطای موقت داشت)،
///  - درخواست رابط کاربری (`scanRecordings`).
class CallEngine {
  CallEngine(this.service);

  final ServiceInstance service;
  final CallCycle _cycle = CallCycle();

  Timer? _timer;
  bool _stopped = false;
  bool _again = false;
  bool _busy = false;

  static const String _lockName = 'calls';
  static const String _slot = 'calls';

  Future<void> start() async {
    service.on('scanRecordings').listen((_) => unawaited(_runSoon()));
    service.on('stopService').listen((_) {
      _stopped = true;
      _timer?.cancel();
      unawaited(SmsBridge.cancelWake(slot: _slot));
    });
    WakeHub.add((reason) {
      if (reason == 'call_ended' ||
          reason == 'calls' ||
          reason == 'recordings' ||
          reason == 'boot') {
        unawaited(_runSoon());
      }
    });
    unawaited(_runSoon());
  }

  Future<void> _runSoon() async {
    if (_stopped) return;
    if (_busy) {
      _again = true; // وقتی چرخه‌ی فعلی تمام شد یک دور دیگر
      return;
    }
    _busy = true; // پیش از اولین await: دو محرکِ هم‌زمان نباید قفل همدیگر را رها کنند
    await LockCoordinator.acquire(_lockName);
    DateTime? next;
    try {
      final report = await _cycle.run();
      next = report.nextDueAt;
      final deferred = report.scan?.deferred ?? 0;
      if (deferred > 0) {
        // فایلی هنوز در حال نوشته‌شدن است؛ چند ثانیه بعد دوباره
        final retry = DateTime.now().add(const Duration(seconds: 45));
        if (next == null || retry.isBefore(next)) next = retry;
      }
      if ((report.scan?.imported ?? 0) > 0 || report.processed > 0) {
        service.invoke('recordingsChanged', {
          'imported': report.scan?.imported ?? 0,
          'processed': report.processed,
        });
      }
    } catch (_) {
      next = DateTime.now().add(const Duration(minutes: 10));
    } finally {
      await LockCoordinator.release(_lockName);
      _busy = false;
    }

    _timer?.cancel();
    if (next != null && !_stopped) {
      unawaited(SmsBridge.scheduleWake(next, reason: 'calls', slot: _slot));
      final delay = next.difference(DateTime.now());
      _timer = Timer(
        delay <= Duration.zero ? const Duration(seconds: 1) : delay,
        () => unawaited(_runSoon()),
      );
    } else {
      unawaited(SmsBridge.cancelWake(slot: _slot));
    }
    if (_again) {
      _again = false;
      unawaited(_runSoon());
    }
  }
}
