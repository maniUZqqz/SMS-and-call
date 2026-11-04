import 'package:flutter/material.dart';
import 'package:untitled3/app/app.dart';
import 'package:untitled3/services/background_service.dart';

export 'package:untitled3/app/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}
