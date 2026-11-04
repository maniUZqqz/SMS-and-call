import 'package:flutter_test/flutter_test.dart';
import 'package:sms_and_call/features/campaigns/domain/scheduled_campaign.dart';

// Reproduction (expected to FAIL on the original code):
// campaign dates were stored as the epoch milliseconds of *local midnight*. When the
// phone's time zone changed between saving and reading (travel, automatic time zone,
// outdated Iranian tzdata with summer time) the start/end day shifted by one day, so the
// campaign ran a day early/late or was closed as "window ended".
void main() {
  test('campaign start/end are stored as a calendar day (yyyy-MM-dd), not an instant', () {
    final campaign = ScheduledCampaign(
      id: 'c1',
      title: 'تست',
      message: 'سلام',
      audience: CampaignAudience.allAtStart,
      startDate: DateTime(2026, 10, 26),
      endDate: DateTime(2026, 10, 28),
      dailyStartMinute: 8 * 60,
      dailyEndMinute: 20 * 60,
      intervalSeconds: 30,
      createdAt: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 10, 20),
    );

    final json = campaign.toJson();

    expect(json['startDate'], '2026-10-26');
    expect(json['endDate'], '2026-10-28');
  });
}
