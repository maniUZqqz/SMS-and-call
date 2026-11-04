import 'dart:async';

import 'package:flutter/services.dart';

int _i(dynamic v, int d) => v is num ? v.toInt() : d;
bool _b(dynamic v, bool d) => v is bool ? v : d;
String _s(dynamic v) => v == null ? '' : v.toString();

/// یک سیم‌کارت فعال روی گوشی
class SimCard {
  final int subscriptionId;
  final int slot; // از 0 شروع می‌شود
  final String name;
  final String carrier;
  final String number;
  final String country;
  final bool embedded;

  const SimCard({
    required this.subscriptionId,
    required this.slot,
    required this.name,
    required this.carrier,
    required this.number,
    required this.country,
    required this.embedded,
  });

  factory SimCard.fromMap(Map<String, dynamic> m) => SimCard(
        subscriptionId: _i(m['subId'], -1),
        slot: _i(m['slot'], -1),
        name: _s(m['name']),
        carrier: _s(m['carrier']),
        number: _s(m['number']),
        country: _s(m['country']),
        embedded: _b(m['embedded'], false),
      );

  String get slotLabel => 'SIM ${slot + 1}';

  String get title {
    final n = carrier.trim().isNotEmpty ? carrier.trim() : name.trim();
    return n.isEmpty ? slotLabel : '$slotLabel · $n';
  }
}

class SimQuery {
  final bool permissionGranted;
  final List<SimCard> sims;
  final int defaultSmsSubId;

  const SimQuery({
    required this.permissionGranted,
    required this.sims,
    required this.defaultSmsSubId,
  });

  static const SimQuery empty =
      SimQuery(permissionGranted: false, sims: [], defaultSmsSubId: -1);
}

/// نتیجه ارسال پیامک. code == 0 یعنی موفق؛ مقادیر مثبت کدهای SmsManager.RESULT_*
/// و مقادیر منفی کدهای داخلی این افزونه هستند:
/// -100 timeout · -101 سیم‌کارت فعال نیست · -102 استثنا · -103 مجوز ندارد
/// -104 قابلیت تلفن ندارد · -105 ورودی خالی · -106 افزونه بومی پیدا نشد
class SmsSendResult {
  final bool ok;
  final int code;
  final int parts;
  final int partsOk;
  final int subId;
  final int usedSubId;
  final int modemCode;
  final String error;

  const SmsSendResult({
    required this.ok,
    required this.code,
    required this.parts,
    required this.partsOk,
    required this.subId,
    required this.usedSubId,
    required this.modemCode,
    required this.error,
  });

  factory SmsSendResult.fromMap(Map<String, dynamic> m) => SmsSendResult(
        ok: _b(m['ok'], false),
        code: _i(m['code'], -102),
        parts: _i(m['parts'], 0),
        partsOk: _i(m['partsOk'], 0),
        subId: _i(m['subId'], -1),
        usedSubId: _i(m['usedSubId'], -1),
        modemCode: _i(m['modemCode'], -1),
        error: _s(m['error']),
      );

  factory SmsSendResult.failure(int code, String error, {int subId = -1}) =>
      SmsSendResult(
        ok: false,
        code: code,
        parts: 0,
        partsOk: 0,
        subId: subId,
        usedSubId: subId,
        modemCode: -1,
        error: error,
      );
}

/// وضعیت مجوزها و محیط دستگاه (از سمت بومی خوانده می‌شود، بدون نیاز به Activity)
class BridgeStatus {
  final bool available; // افزونه بومی در این engine ثبت شده؟
  final bool sendSms;
  final bool phoneState;
  final bool phoneNumbers;
  final bool notifications;
  final bool battery; // true = از بهینه‌سازی باتری مستثنا است
  final bool airplane;
  final bool telephony;
  final int sdk;
  final String manufacturer;
  final String model;

  const BridgeStatus({
    required this.available,
    required this.sendSms,
    required this.phoneState,
    required this.phoneNumbers,
    required this.notifications,
    required this.battery,
    required this.airplane,
    required this.telephony,
    required this.sdk,
    required this.manufacturer,
    required this.model,
  });

  static const BridgeStatus unknown = BridgeStatus(
    available: false,
    sendSms: false,
    phoneState: false,
    phoneNumbers: false,
    notifications: false,
    battery: false,
    airplane: false,
    telephony: true,
    sdk: 0,
    manufacturer: '',
    model: '',
  );

  factory BridgeStatus.fromMap(Map<String, dynamic> m) => BridgeStatus(
        available: true,
        sendSms: _b(m['sendSms'], false),
        phoneState: _b(m['phoneState'], false),
        phoneNumbers: _b(m['phoneNumbers'], false),
        notifications: _b(m['notifications'], false),
        battery: _b(m['battery'], false),
        airplane: _b(m['airplane'], false),
        telephony: _b(m['telephony'], true),
        sdk: _i(m['sdk'], 0),
        manufacturer: _s(m['manufacturer']),
        model: _s(m['model']),
      );
}

class PickedContactFile {
  const PickedContactFile({required this.path, required this.name});

  final String path;
  final String name;
}

class SmsBridge {
  SmsBridge._();

  static const MethodChannel _ch = MethodChannel('sms_bridge');

  /// مسیر پایدار filesDir برنامه (برخلاف cache پاک نمی‌شود)
  static Future<String> filesDir() async {
    try {
      return (await _ch.invokeMethod<String>('filesDir')) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<PickedContactFile?> pickContactFile() async {
    final result = await _ch.invokeMapMethod<String, dynamic>(
      'pickContactFile',
    );
    if (result == null) return null;
    final path = _s(result['path']);
    if (path.isEmpty) return null;
    return PickedContactFile(path: path, name: _s(result['name']));
  }

  static Future<BridgeStatus> status() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('status');
      if (m == null) return BridgeStatus.unknown;
      return BridgeStatus.fromMap(m);
    } catch (_) {
      return BridgeStatus.unknown;
    }
  }

  static Future<SimQuery> getSimCards() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('getSimCards');
      if (m == null) return SimQuery.empty;
      final raw = m['sims'];
      final sims = <SimCard>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            sims.add(SimCard.fromMap(Map<String, dynamic>.from(e)));
          }
        }
      }
      sims.sort((a, b) => a.slot.compareTo(b.slot));
      return SimQuery(
        permissionGranted: _b(m['permission'], false),
        sims: sims,
        defaultSmsSubId: _i(m['defaultSmsSubId'], -1),
      );
    } catch (_) {
      return SimQuery.empty;
    }
  }

  /// subId < 0 یعنی سیم‌کارت پیش‌فرض پیامک گوشی.
  /// این متد هرگز استثنا پرتاب نمی‌کند؛ همیشه یک [SmsSendResult] برمی‌گرداند.
  static Future<SmsSendResult> sendSms({
    required String to,
    required String message,
    int subId = -1,
  }) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('sendSms', {
        'to': to,
        'message': message,
        'subId': subId,
      }).timeout(const Duration(seconds: 75));
      if (m == null) {
        return SmsSendResult.failure(-102, 'پاسخ خالی از لایه بومی',
            subId: subId);
      }
      return SmsSendResult.fromMap(m);
    } on TimeoutException {
      return SmsSendResult.failure(-100, 'گزارش ارسال از سیستم نرسید',
          subId: subId);
    } on MissingPluginException catch (e) {
      return SmsSendResult.failure(-106, e.toString(), subId: subId);
    } on PlatformException catch (e) {
      return SmsSendResult.failure(-102, '${e.code}: ${e.message}',
          subId: subId);
    } catch (e) {
      return SmsSendResult.failure(-102, e.toString(), subId: subId);
    }
  }

  /// قفل CPU و Wi-Fi تا سرویس پس‌زمینه در حالت خواب (Doze) متوقف نشود
  static Future<void> acquireLocks() async {
    try {
      await _ch.invokeMethod<bool>('acquireLocks');
    } catch (_) {}
  }

  static Future<void> releaseLocks() async {
    try {
      await _ch.invokeMethod<bool>('releaseLocks');
    } catch (_) {}
  }
}
