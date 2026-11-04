import 'package:flutter_test/flutter_test.dart';
import 'package:sms_and_call/features/campaigns/domain/schedule_planner.dart';
import 'package:sms_and_call/features/campaigns/domain/scheduled_campaign.dart';

ScheduledCampaign _c(
  String id, {
  required DateTime start,
  required DateTime end,
  int dailyStart = 8 * 60,
  int dailyEnd = 20 * 60,
  ScheduledCampaignState state = ScheduledCampaignState.waiting,
}) {
  return ScheduledCampaign(
    id: id,
    title: id,
    message: 'سلام',
    audience: CampaignAudience.allAtStart,
    startDate: start,
    endDate: end,
    dailyStartMinute: dailyStart,
    dailyEndMinute: dailyEnd,
    intervalSeconds: 30,
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
    state: state,
  );
}

void main() {
  group('planNextWake — what the OS alarm is armed for', () {
    test('nothing to do when there are no active campaigns', () {
      expect(planNextWake(const [], DateTime(2026, 11, 4, 12)), isNull);
      expect(
        planNextWake([
          _c(
            'done',
            start: DateTime(2026, 11, 1),
            end: DateTime(2026, 11, 2),
            state: ScheduledCampaignState.completed,
          ),
        ], DateTime(2026, 11, 4, 12)),
        isNull,
      );
    });

    test('a campaign starting tomorrow wakes the phone at its first window', () {
      final wake = planNextWake([
        _c('a', start: DateTime(2026, 11, 5), end: DateTime(2026, 11, 7)),
      ], DateTime(2026, 11, 4, 22));

      expect(wake!.at, DateTime(2026, 11, 5, 8));
      expect(wake.reason, WakeReason.sendWindow);
    });

    test('between two daily windows it wakes at the next morning', () {
      final wake = planNextWake([
        _c('a', start: DateTime(2026, 11, 4), end: DateTime(2026, 11, 7)),
      ], DateTime(2026, 11, 4, 21));

      expect(wake!.at, DateTime(2026, 11, 5, 8));
    });

    test('inside the window it wakes immediately', () {
      final now = DateTime(2026, 11, 4, 12, 30);
      final wake = planNextWake([
        _c('a', start: DateTime(2026, 11, 4), end: DateTime(2026, 11, 7)),
      ], now);

      expect(wake!.at, now);
    });

    test('the earliest of several campaigns wins', () {
      final wake = planNextWake([
        _c('late', start: DateTime(2026, 11, 9), end: DateTime(2026, 11, 10)),
        _c('soon', start: DateTime(2026, 11, 5), end: DateTime(2026, 11, 5)),
      ], DateTime(2026, 11, 4, 12));

      expect(wake!.at, DateTime(2026, 11, 5, 8));
    });

    test('an overdue campaign must be closed right now', () {
      final now = DateTime(2026, 11, 10, 9);
      final wake = planNextWake([
        _c('old', start: DateTime(2026, 11, 5), end: DateTime(2026, 11, 7)),
      ], now);

      expect(wake!.at, now);
      expect(wake.reason, WakeReason.expiry);
    });
  });

  group('dueCampaigns / expiredCampaigns', () {
    final campaigns = [
      _c('running', start: DateTime(2026, 11, 4), end: DateTime(2026, 11, 7)),
      _c('future', start: DateTime(2026, 11, 8), end: DateTime(2026, 11, 9)),
      _c('over', start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 2)),
    ];

    test('only campaigns inside their window are due', () {
      final due = dueCampaigns(campaigns, DateTime(2026, 11, 4, 12));
      expect(due.map((c) => c.id), ['running']);
    });

    test('outside the daily window nothing is due', () {
      expect(dueCampaigns(campaigns, DateTime(2026, 11, 4, 23)), isEmpty);
    });

    test('expired campaigns are the ones past their end', () {
      final expired = expiredCampaigns(campaigns, DateTime(2026, 11, 4, 12));
      expect(expired.map((c) => c.id), ['over']);
    });

    test('a campaign that is already terminal is never expired again', () {
      final done = _c(
        'over',
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 2),
        state: ScheduledCampaignState.windowEnded,
      );
      expect(expiredCampaigns([done], DateTime(2026, 11, 4)), isEmpty);
    });
  });
}
