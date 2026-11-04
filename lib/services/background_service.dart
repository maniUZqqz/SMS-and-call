import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/core/constants/app_constants.dart';
import 'package:sms_and_call/features/calls/services/call_engine.dart';
import 'package:sms_and_call/features/contacts/services/campaign_engine.dart';
import 'package:sms_and_call/features/gateway/services/gateway_engine.dart';
import 'package:sms_and_call/services/lock_coordinator.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      autoStartOnBoot: true,
      isForegroundMode: true,
      initialNotificationTitle: 'پیامک و تماس',
      initialNotificationContent: 'در حال آماده‌سازی…',
      foregroundServiceNotificationId: kNotificationId,
      foregroundServiceTypes: [AndroidForegroundType.specialUse],
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  // لازم برای استفاده از MethodChannel در isolate پس‌زمینه
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // آلارم سیستم‌عامل (WakeReceiver) به همین ایزوله می‌رسد و بخش‌ها را بیدار می‌کند
  SmsBridge.setWakeHandler(WakeHub.dispatch);

  final campaignEngine = CampaignEngine(service);
  final engine = GatewayEngine(service);
  final callEngine = CallEngine(service);

  // خرابی یک بخش نباید بخش‌های دیگر را از شروع بازدارد
  for (final start in <Future<void> Function()>[
    campaignEngine.start,
    engine.start,
    callEngine.start,
  ]) {
    try {
      await start();
    } catch (_) {}
  }
}
