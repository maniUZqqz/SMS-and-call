import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:untitled3/core/constants/app_constants.dart';
import 'package:untitled3/features/contacts/services/campaign_engine.dart';
import 'package:untitled3/features/gateway/services/gateway_engine.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      autoStartOnBoot: true,
      isForegroundMode: true,
      initialNotificationTitle: 'گیت‌وی پیامک',
      initialNotificationContent: 'در حال اتصال به سرور...',
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

  final campaignEngine = CampaignEngine(service);
  final engine = GatewayEngine(service);

  await campaignEngine.start();
  await engine.start();
}
