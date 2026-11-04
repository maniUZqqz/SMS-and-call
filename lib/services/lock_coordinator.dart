import 'dart:async';

import 'package:sms_bridge/sms_bridge.dart';

/// هماهنگ‌کننده‌ی قفل‌های CPU و Wi-Fi داخل ایزوله‌ی سرویس.
///
/// هر بخش (گیت‌وی، ارسال کمپین، پردازش ضبط‌ها…) فقط وقتی کار دارد قفل می‌گیرد و پایان
/// کار آن را رها می‌کند. وقتی هیچ‌کس قفلی لازم ندارد، CPU اجازه‌ی خواب دارد و بیدارشدن
/// بعدی با آلارم سیستم‌عامل انجام می‌شود (باتری گوشی را در حالت بیکار نمی‌خورد).
class LockCoordinator {
  LockCoordinator._();

  static final Map<String, bool> _holders = <String, bool>{};

  /// [needsWifi] فقط برای کارهایی است که اینترنت می‌خواهند (مثل گیت‌وی).
  static Future<void> acquire(String holder, {bool needsWifi = false}) async {
    _holders[holder] = needsWifi;
    await _sync();
  }

  static Future<void> release(String holder) async {
    if (_holders.remove(holder) == null) return;
    await _sync();
  }

  static bool get anyHeld => _holders.isNotEmpty;

  static Future<void> _sync() async {
    final cpu = _holders.isNotEmpty;
    final wifi = _holders.values.any((needsWifi) => needsWifi);
    await SmsBridge.setLocks(cpu: cpu, wifi: wifi);
  }

  /// فقط برای تست.
  static void resetForTests() => _holders.clear();
}

/// پیام «بیدار شو» از سمت بومی (آلارم) را به همه‌ی بخش‌های سرویس می‌رساند.
class WakeHub {
  WakeHub._();

  static final List<void Function(String reason)> _listeners =
      <void Function(String reason)>[];

  static void add(void Function(String reason) listener) {
    _listeners.add(listener);
  }

  static void dispatch(String reason) {
    for (final listener in List.of(_listeners)) {
      try {
        listener(reason);
      } catch (_) {}
    }
  }

  static void resetForTests() => _listeners.clear();
}
