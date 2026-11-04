import 'package:flutter/material.dart' hide StepState;
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/home/presentation/pages/activity_tab.dart';
import 'package:untitled3/features/home/presentation/pages/dashboard_tab.dart';
import 'package:untitled3/features/home/presentation/pages/settings_tab.dart';
import 'package:untitled3/features/logs/domain/log_entry.dart';
import 'package:untitled3/features/settings/domain/server_config.dart';

void main() {
  Widget testShell(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('dashboard fits a compact phone viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      testShell(
        DashboardTab(
          running: true,
          connectionLabel: 'متصل به سرور · 42ms',
          connectionDetail: null,
          connectionColor: AppColors.success,
          connectionIcon: Icons.play_circle_rounded,
          sent: 12,
          failed: 1,
          polls: 240,
          nativeBridgeAvailable: true,
          smsPermissionGranted: true,
          missingPermissions: 0,
          serverUrl: 'http://192.168.43.47:5000',
          simTitle: 'SIM 1 · همراه اول',
          messagePreview: 'کد تایید شما: ۱۲۳۴۵۶',
          latestLog: LogEntry(
            kind: LogKind.flow,
            title: 'کد تایید برای 09120000000',
            steps: [FlowStep('ارسال پیامک', state: StepState.ok)],
          ),
          onRefresh: () async {},
          onStart: () {},
          onStop: () {},
          onOpenPermissions: () {},
          onOpenServer: () {},
          onOpenSms: () {},
          onOpenActivity: () {},
        ),
      ),
    );

    expect(find.text('گیت‌وی فعال'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity tab shows filters and logs without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final entry = LogEntry(
      kind: LogKind.response,
      level: LogLevel.warning,
      title: 'پاسخ سرور نیاز به بررسی دارد',
      detail: 'نمونه گزارش برای تست رابط کاربری',
    );

    await tester.pumpWidget(
      testShell(
        ActivityTab(
          logs: [entry],
          filter: LogFilter.all,
          expandedIds: const {},
          onFilterChanged: (_) {},
          onToggleExpanded: (_) {},
          onCopyOne: (_) {},
          onCopyAll: () {},
          onClear: () {},
        ),
      ),
    );

    expect(find.text('1 رویداد ذخیره‌شده'), findsOneWidget);
    expect(find.text('همه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings tab keeps all configuration groups accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const status = BridgeStatus(
      available: true,
      sendSms: true,
      phoneState: true,
      phoneNumbers: true,
      notifications: true,
      battery: true,
      airplane: false,
      telephony: true,
      sdk: 35,
      manufacturer: 'Google',
      model: 'Pixel',
    );

    await tester.pumpWidget(
      testShell(
        SettingsTab(
          config: ServerConfig.defaults(),
          bridgeStatus: status,
          running: true,
          missingPermissions: 0,
          onOpenServer: () {},
          onOpenSms: () {},
          onOpenPermissions: () {},
          onStart: () {},
          onStop: () {},
        ),
      ),
    );

    expect(find.text('تنظیمات سرور'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.text('دستگاه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
