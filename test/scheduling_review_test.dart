import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/core/storage/app_storage.dart';
import 'package:sms_and_call/features/campaigns/data/scheduled_campaign_storage.dart';
import 'package:sms_and_call/features/campaigns/domain/schedule_planner.dart';
import 'package:sms_and_call/features/campaigns/domain/scheduled_campaign.dart';
import 'package:sms_and_call/features/campaigns/services/campaign_runner.dart';
import 'package:sms_and_call/features/contacts/domain/sms_campaign.dart';

ScheduledCampaign _scheduled(String id, {SmsCampaign? execution}) {
  return ScheduledCampaign(
    id: id,
    title: id,
    message: 'سلام',
    audience: CampaignAudience.selected,
    selectedRecipients: const [
      CampaignRecipient(contactId: '1', name: 'الف', phone: '09120000001'),
    ],
    startDate: DateTime(2026, 11, 4),
    endDate: DateTime(2026, 11, 6),
    dailyStartMinute: 8 * 60,
    dailyEndMinute: 20 * 60,
    intervalSeconds: 30,
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
    state: ScheduledCampaignState.waiting,
    execution: execution,
  );
}

SmsCampaign _runtime({DateTime? notBefore}) => SmsCampaign(
  id: 'x',
  message: 'سلام',
  recipients: const [
    CampaignRecipient(contactId: '1', name: 'الف', phone: '09120000001'),
    CampaignRecipient(contactId: '2', name: 'ب', phone: '09120000002'),
  ],
  intervalSeconds: 30,
  startsAt: DateTime(2026, 11, 4, 8),
  endsAt: DateTime(2026, 11, 6, 20),
  dailyStartMinute: 8 * 60,
  dailyEndMinute: 20 * 60,
  nextIndex: 1,
  sentCount: 1,
  sentRecipientIds: const ['1'],
  notBefore: notBefore,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 4, 12, 0);

  group('a paused campaign is not "due now" while its notBefore is in the future', () {
    // پیش‌تر کمپینِ در مکثِ ۴۰ دقیقه‌ای (سقف ساعتی) در هر دور «سررسید» حساب می‌شد و
    // بی‌وقفه شروع و متوقف می‌شد (حلقه‌ی پرمصرف).
    final paused = _scheduled('p', execution: _runtime(notBefore: DateTime(2026, 11, 4, 12, 40)));

    test('it is not due, and the alarm is armed for the notBefore time', () {
      expect(dueCampaigns([paused], now), isEmpty);
      final wake = planNextWake([paused], now);
      expect(wake!.at, DateTime(2026, 11, 4, 12, 40));
    });

    test('once notBefore passes it is due again', () {
      final later = DateTime(2026, 11, 4, 12, 41);
      expect(dueCampaigns([paused], later).map((c) => c.id), ['p']);
    });

    test('a notBefore after the daily window moves the wake to the next morning', () {
      final overnight = _scheduled('o', execution: _runtime(notBefore: DateTime(2026, 11, 4, 22)));
      expect(planNextWake([overnight], now)!.at, DateTime(2026, 11, 5, 8));
    });
  });

  test('a multi-part SMS that was only partly accepted is never resent', () {
    const partial = SmsSendResult(
      ok: false,
      code: 1,
      parts: 2,
      partsOk: 1,
      subId: 1,
      usedSubId: 1,
      modemCode: -1,
      error: '',
    );
    expect(classifySendFailure(partial), SendFailureKind.uncertain);
    const none = SmsSendResult(ok: false, code: 4, parts: 2, partsOk: 0, subId: 1, usedSubId: 1, modemCode: -1, error: '');
    expect(classifySendFailure(none), SendFailureKind.transient);
  });

  group('storage under concurrent writers', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('conc-');
      AppDir.setPathForTests(dir.path);
    });
    tearDown(() async {
      AppDir.setPathForTests(null);
      await dir.delete(recursive: true);
    });

    test('parallel upserts of different campaigns all survive', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++) ScheduledCampaignStorage.upsert(_scheduled('c$i')),
      ]);
      expect((await ScheduledCampaignStorage.load()), hasLength(20));
    });

    test('parallel atomic writes to one file never throw', () async {
      final file = File('${dir.path}/shared.json');
      await Future.wait([
        for (var i = 0; i < 30; i++) writeAtomicFile(file, '{"n":$i}'),
      ]);
      expect(jsonDecode(file.readAsStringSync()), isA<Map>());
      expect(
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
    });
  });
}
