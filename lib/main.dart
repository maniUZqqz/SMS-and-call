import 'package:flutter/material.dart';
import 'package:sms_and_call/app/app.dart';
import 'package:sms_and_call/services/background_service.dart';

export 'package:sms_and_call/app/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}
