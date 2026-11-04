import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/features/campaigns/services/campaign_runner.dart';
import 'package:sms_and_call/features/contacts/domain/contact.dart';
import 'package:sms_and_call/features/contacts/domain/sms_campaign.dart';
import 'package:sms_and_call/features/settings/domain/send_settings.dart';

/// ساعت جعلی: sleep فقط زمان را جلو می‌برد (تست‌ها آنی اجرا می‌شوند).
class FakeClock {
  FakeClock(this.now);

  DateTime now;

  Future<void> sleep(Duration duration) async {
    now = now.add(duration);
  }

  DateTime call() => now;
}

SmsSendResult _ok() => const SmsSendResult(
  ok: true,
  code: 0,
  parts: 1,
  partsOk: 1,
  subId: 1,
  usedSubId: 1,
  modemCode: -1,
  error: '',
);

SmsSendResult _fail(int code) => SmsSendResult(
  ok: false,
  code: code,
  parts: 1,
  partsOk: 0,
  subId: 1,
  usedSubId: 1,
  modemCode: -1,
  error: '',
);

class SentCall {
  SentCall(this.to, this.at);

  final String to;
  final DateTime at;
}

/// فرستنده‌ی جعلی: نتیجه‌ها به ترتیب مصرف می‌شوند؛ بعد از آن‌ها همه موفق.
class FakeSender {
  FakeSender(this.clock, [List<SmsSendResult> script = const []])
    : _script = List.of(script);

  final FakeClock clock;
  final List<SmsSendResult> _script;
  final List<SentCall> calls = [];

  Future<SmsSendResult> call({
    required String to,
    required String message,
    required int subId,
  }) async {
    calls.add(SentCall(to, clock.now));
    return _script.isEmpty ? _ok() : _script.removeAt(0);
  }
}

List<CampaignRecipient> _people(List<String> phones) => [
  for (var i = 0; i < phones.length; i++)
    CampaignRecipient(contactId: 'c$i', name: 'نفر $i', phone: phones[i]),
];

SmsCampaign _campaign(
  List<String> phones,
  DateTime start, {
  int interval = 30,
  Duration length = const Duration(days: 1),
  int? dailyStart,
  int? dailyEnd,
  String? scheduledId,
  int inFlight = -1,
  int attempt = 0,
}) {
  return SmsCampaign(
    id: 'camp',
    message: 'سلام',
    recipients: _people(phones),
    intervalSeconds: interval,
    startsAt: start,
    endsAt: start.add(length),
    dailyStartMinute: dailyStart,
    dailyEndMinute: dailyEnd,
    scheduledCampaignId: scheduledId,
    inFlightIndex: inFlight,
    attempt: attempt,
  );
}

CampaignRunner _runner(
  FakeClock clock,
  FakeSender sender, {
  Set<String> optOut = const {},
  SendSettings settings = const SendSettings(jitterPercent: 0),
  SendLedger? ledger,
  Future<void> Function(SmsCampaign, CampaignState)? onProgress,
}) {
  return CampaignRunner(
    send: sender.call,
    onProgress:
        (campaign, state, {currentContact, lastSendSucceeded, note}) async {
          await onProgress?.call(campaign, state);
        },
    loadOptOutKeys: () async => optOut,
    settings: () => settings,
    ledger: ledger ?? SendLedger(),
    resolveSubId: () async => 1,
    clock: clock.call,
    sleep: clock.sleep,
    random: Random(1),
  );
}

void main() {
  final t0 = DateTime(2026, 11, 4, 10, 0, 0);

  group('throttling', () {
    test('never sends faster than the configured minimum delay', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final runner = _runner(
        clock,
        sender,
        settings: const SendSettings(minDelaySeconds: 20, jitterPercent: 0),
      );

      // فاصله‌ی انتخابی کمپین (۵ ثانیه) از حداقل تنظیمات (۲۰ ثانیه) کمتر است
      final result = await runner.run(
        _campaign(['09120000001', '09120000002', '09120000003'], t0, interval: 5),
      );

      expect(result.status, RunStatus.completed);
      expect(sender.calls.map((c) => c.at.difference(t0).inSeconds), [0, 20, 40]);
    });

    test('keeps a campaign interval that is longer than the minimum', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final runner = _runner(clock, sender);

      await runner.run(_campaign(['09120000001', '09120000002'], t0, interval: 60));

      expect(sender.calls.map((c) => c.at.difference(t0).inSeconds), [0, 60]);
    });

    test('jitter only ever adds time, never removes it', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final runner = _runner(
        clock,
        sender,
        settings: const SendSettings(minDelaySeconds: 10, jitterPercent: 50),
      );

      await runner.run(
        _campaign(
          ['09120000001', '09120000002', '09120000003', '09120000004'],
          t0,
          interval: 10,
        ),
      );

      for (var i = 1; i < sender.calls.length; i++) {
        final gap = sender.calls[i].at.difference(sender.calls[i - 1].at);
        expect(gap.inMilliseconds, inInclusiveRange(10000, 15000));
      }
    });

    test('hourly cap pauses the campaign and resumes when a slot frees up', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final ledger = SendLedger();
      const settings = SendSettings(
        minDelaySeconds: 3,
        jitterPercent: 0,
        maxPerHour: 2,
      );
      final phones = ['09120000001', '09120000002', '09120000003', '09120000004'];

      final first = await _runner(
        clock,
        sender,
        settings: settings,
        ledger: ledger,
      ).run(_campaign(phones, t0, interval: 3));

      expect(first.status, RunStatus.paused);
      expect(sender.calls, hasLength(2));
      expect(first.campaign.nextIndex, 2);
      expect(first.resumeAt, t0.add(const Duration(hours: 1)));

      // یک ساعت بعد، با همان سابقه‌ی ارسال، ادامه می‌دهد
      clock.now = first.resumeAt!;
      final second = await _runner(
        clock,
        sender,
        settings: settings,
        ledger: ledger,
      ).run(first.campaign);

      expect(sender.calls.map((c) => c.to).toList().sublist(2).first, '09120000003');
      expect(second.campaign.sentCount, greaterThanOrEqualTo(3));
    });
  });

  group('opt-out list', () {
    test('numbers marked as opted out are never sent to', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final runner = _runner(
        clock,
        sender,
        optOut: {phoneKey('09120000002')},
      );

      final result = await runner.run(
        _campaign(['09120000001', '09120000002', '09120000003'], t0),
      );

      expect(result.status, RunStatus.completed);
      expect(sender.calls.map((c) => c.to), ['09120000001', '09120000003']);
      expect(result.campaign.skipped, {'c1': 'optout'});
      expect(result.campaign.sentCount, 2);
      expect(result.campaign.failedCount, 0);
    });

    test('matches the number whatever format it is written in', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      // در فهرست لغو با +98 ثبت شده، در کمپین با 0912
      final runner = _runner(clock, sender, optOut: {phoneKey('+989123456789')});

      final result = await runner.run(_campaign(['09123456789'], t0));

      expect(sender.calls, isEmpty);
      expect(result.campaign.skipped, {'c0': 'optout'});
    });

    test('a number opted out half-way through the run is still honoured', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final optOut = <String>{};
      final runner = CampaignRunner(
        send: sender.call,
        onProgress: (c, s, {currentContact, lastSendSucceeded, note}) async {
          // بعد از پیامک اول، شماره‌ی دوم لغو می‌شود
          if (lastSendSucceeded == true) optOut.add(phoneKey('09120000002'));
        },
        loadOptOutKeys: () async => Set.of(optOut),
        settings: () => const SendSettings(jitterPercent: 0),
        ledger: SendLedger(),
        resolveSubId: () async => 1,
        clock: clock.call,
        sleep: clock.sleep,
      );

      final result = await runner.run(
        _campaign(['09120000001', '09120000002', '09120000003'], t0),
      );

      expect(sender.calls.map((c) => c.to), ['09120000001', '09120000003']);
      expect(result.campaign.skipped.keys, ['c1']);
    });
  });

  group('recipient hygiene', () {
    test('duplicate numbers get one message only', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final result = await _runner(clock, sender).run(
        _campaign(['09120000001', '+989120000001', '09120000002'], t0),
      );

      expect(sender.calls.map((c) => c.to), ['09120000001', '09120000002']);
      expect(result.campaign.skipped, {'c1': 'duplicate'});
    });

    test('invalid numbers are skipped, not sent', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final result = await _runner(clock, sender).run(
        _campaign(['12', '09120000002'], t0),
      );

      expect(sender.calls.map((c) => c.to), ['09120000002']);
      expect(result.campaign.skipped, {'c0': 'invalid'});
    });
  });

  group('failures', () {
    test('a transient failure is retried after a back-off and then succeeds', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock, [_fail(4)]); // آنتن نیست
      final result = await _runner(clock, sender).run(
        _campaign(['09120000001', '09120000002'], t0),
      );

      expect(result.status, RunStatus.completed);
      expect(result.campaign.sentCount, 2);
      expect(result.campaign.failedCount, 0);
      expect(sender.calls.map((c) => c.to).take(2), ['09120000001', '09120000001']);
      expect(sender.calls[1].at.difference(sender.calls[0].at).inSeconds, 30);
    });

    test('a recipient is given up on after the configured retries, the rest continue', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock, [_fail(4), _fail(4), _fail(4)]);
      final result = await _runner(clock, sender).run(
        _campaign(['09120000001', '09120000002'], t0),
      );

      expect(result.status, RunStatus.completed);
      expect(result.campaign.failedRecipientIds, ['c0']);
      expect(result.campaign.sentRecipientIds, ['c1']);
      expect(sender.calls.where((c) => c.to == '09120000001'), hasLength(3));
      expect(result.campaign.failureNotes.keys, ['c0']);
    });

    test('repeated failures pause sending instead of burning through the list', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock, [_fail(4), _fail(4)]);
      const settings = SendSettings(
        minDelaySeconds: 10,
        jitterPercent: 0,
        retryAttempts: 5,
        pauseAfterFailures: 2,
        pauseMinutes: 5,
      );
      await _runner(clock, sender, settings: settings).run(
        _campaign(['09120000001', '09120000002'], t0),
      );

      // ۰، ۳۰ ثانیه بعد (شکست دوم)، و بعد ۵ دقیقه مکث
      expect(sender.calls.map((c) => c.at.difference(t0).inSeconds).take(3), [0, 30, 330]);
    });

    test('a permanent failure is not retried', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock, [_fail(3)]); // PDU ناممکن
      final result = await _runner(clock, sender).run(
        _campaign(['09120000001', '09120000002'], t0),
      );

      expect(sender.calls.where((c) => c.to == '09120000001'), hasLength(1));
      expect(result.campaign.failedRecipientIds, ['c0']);
      expect(result.campaign.sentRecipientIds, ['c1']);
    });

    test('a timed-out send is never repeated (it may already have been delivered)', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock, [_fail(-100)]);
      final result = await _runner(clock, sender).run(
        _campaign(['09120000001', '09120000002'], t0),
      );

      expect(sender.calls.where((c) => c.to == '09120000001'), hasLength(1));
      expect(result.campaign.failedRecipientIds, ['c0']);
      expect(result.campaign.failureNotes['c0'], contains('نامعلوم'));
    });

    test('a missing permission stops the whole campaign', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock, [_fail(-103)]);
      final result = await _runner(clock, sender).run(
        _campaign(['09120000001', '09120000002', '09120000003'], t0),
      );

      expect(result.status, RunStatus.failed);
      expect(sender.calls, hasLength(1));
      expect(result.campaign.nextIndex, 0);
      expect(result.campaign.failedCount, 0);
    });

    test('a carrier limit pauses for a long time without failing the recipient', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock, [_fail(5)]);
      final result = await _runner(clock, sender).run(
        _campaign(['09120000001', '09120000002'], t0),
      );

      expect(result.status, RunStatus.paused);
      expect(result.resumeAt, t0.add(const Duration(minutes: 15)));
      expect(result.campaign.nextIndex, 0);
      expect(result.campaign.failedCount, 0);
    });
  });

  group('crash safety', () {
    test('a message that was in flight when the app died is not sent twice', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final interrupted = _campaign(
        ['09120000001', '09120000002'],
        t0,
        inFlight: 0,
        attempt: 1,
      );

      final result = await _runner(clock, sender).run(interrupted);

      expect(sender.calls.map((c) => c.to), ['09120000002']);
      expect(result.campaign.failedRecipientIds, ['c0']);
      expect(result.campaign.failureNotes['c0'], contains('نامعلوم'));
    });

    test('progress is persisted with an in-flight marker before every send', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final seen = <int>[];
      final runner = _runner(
        clock,
        sender,
        onProgress: (campaign, state) async {
          if (state == CampaignState.sending && campaign.inFlightIndex >= 0) {
            seen.add(campaign.inFlightIndex);
          }
        },
      );

      await runner.run(_campaign(['09120000001', '09120000002'], t0));

      expect(seen, [0, 1]);
    });

    test('campaign state survives a JSON round trip', () {
      final base = _campaign(['09120000001'], t0, inFlight: 0, attempt: 2);
      final restored = SmsCampaign.fromJson(
        base
            .copyWith(
              skipped: {'c0': 'optout'},
              failureNotes: {'c0': 'x'},
              notBefore: t0.add(const Duration(minutes: 1)),
            )
            .toJson(),
      );
      expect(restored.inFlightIndex, 0);
      expect(restored.attempt, 2);
      expect(restored.skipped, {'c0': 'optout'});
      expect(restored.notBefore, t0.add(const Duration(minutes: 1)));
    });
  });

  group('windows', () {
    test('waits (in-process) for a start time a few minutes away', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final result = await _runner(clock, sender).run(
        _campaign(['09120000001'], t0.add(const Duration(minutes: 5))),
      );

      expect(result.status, RunStatus.completed);
      expect(sender.calls.single.at, t0.add(const Duration(minutes: 5)));
    });

    test('a start hours away becomes a pause (the OS alarm resumes it)', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      final start = t0.add(const Duration(hours: 3));
      final result = await _runner(clock, sender).run(
        _campaign(['09120000001'], start),
      );

      expect(result.status, RunStatus.paused);
      expect(result.resumeAt, start);
      expect(sender.calls, isEmpty);
    });

    test('daily window end pauses until tomorrow morning', () async {
      final clock = FakeClock(DateTime(2026, 11, 4, 19, 59, 50));
      final sender = FakeSender(clock);
      final campaign = _campaign(
        ['09120000001', '09120000002', '09120000003'],
        DateTime(2026, 11, 4, 8),
        length: const Duration(days: 2, hours: 12),
        dailyStart: 8 * 60,
        dailyEnd: 20 * 60,
        scheduledId: 's1',
      );

      final result = await _runner(clock, sender).run(campaign);

      expect(sender.calls, hasLength(1));
      expect(result.status, RunStatus.paused);
      expect(result.resumeAt, DateTime(2026, 11, 5, 8));
      expect(result.campaign.nextIndex, 1);
    });

    test('ends with "window ended" when the last window closes', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      // پنجره‌ی ۲۵ ثانیه‌ای و فاصله‌ی ۳۰ ثانیه: فقط نفر اول جا می‌شود
      final result = await _runner(clock, sender).run(
        _campaign(
          ['09120000001', '09120000002'],
          t0,
          length: const Duration(seconds: 25),
        ),
      );

      expect(result.status, RunStatus.windowEnded);
      expect(sender.calls, hasLength(1));
      expect(result.campaign.remainingCount, 1);
    });
  });

  group('control', () {
    test('cancel stops after the current message', () async {
      final clock = FakeClock(t0);
      final sender = FakeSender(clock);
      late CampaignRunner runner;
      runner = CampaignRunner(
        send: sender.call,
        onProgress: (c, s, {currentContact, lastSendSucceeded, note}) async {
          if (lastSendSucceeded == true) runner.cancelRequested = true;
        },
        loadOptOutKeys: () async => const {},
        settings: () => const SendSettings(jitterPercent: 0),
        ledger: SendLedger(),
        resolveSubId: () async => 1,
        clock: clock.call,
        sleep: clock.sleep,
      );

      final result = await runner.run(
        _campaign(['09120000001', '09120000002', '09120000003'], t0),
      );

      expect(result.status, RunStatus.cancelled);
      expect(sender.calls, hasLength(1));
    });
  });
}
