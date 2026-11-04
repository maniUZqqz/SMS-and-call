import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/campaigns/presentation/campaign_editor_page.dart';

void main() {
  Widget testShell(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    );
  }

  testWidgets('campaign editor stays usable on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(testShell(const CampaignEditorPage(campaigns: [])));

    expect(find.text('کمپین جدید'), findsOneWidget);
    expect(find.text('پیام کمپین'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('گیرندگان'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ارسال به همه'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('خلاصه اجرای کمپین'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ذخیره و فعال‌سازی کمپین'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Persian range picker opens without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(testShell(const CampaignEditorPage(campaigns: [])));
    await tester.tap(find.text('بازه تاریخ'));
    await tester.pumpAndSettle();

    expect(find.text('بازه تاریخ کمپین'), findsOneWidget);
    expect(find.text('تأیید بازه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
