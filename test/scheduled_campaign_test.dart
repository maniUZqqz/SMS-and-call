import 'package:flutter_test/flutter_test.dart';
import 'package:untitled3/core/utils/persian_date.dart';
import 'package:untitled3/features/campaigns/domain/scheduled_campaign.dart';
import 'package:untitled3/features/contacts/domain/sms_campaign.dart';

void main() {
  group('Persian calendar', () {
    test('converts known new-year dates in both directions', () {
      expect(
        PersianDate.fromDateTime(DateTime(2024, 3, 20)),
        const PersianDate(1403, 1, 1),
      );
      expect(
        PersianDate.fromDateTime(DateTime(2025, 3, 21)),
        const PersianDate(1404, 1, 1),
      );
      expect(const PersianDate(1403, 1, 1).toDateTime(), DateTime(2024, 3, 20));
      expect(const PersianDate(1404, 1, 1).toDateTime(), DateTime(2025, 3, 21));
    });

    test('round-trips dates and detects Esfand length', () {
      for (
        var day = DateTime(2020, 1, 1);
        day.isBefore(DateTime(2031, 1, 1));
        day = day.add(const Duration(days: 17))
      ) {
        expect(PersianDate.fromDateTime(day).toDateTime(), dateOnly(day));
      }
      expect(const PersianDate(1399, 12, 1).daysInMonth, 30);
      expect(const PersianDate(1402, 12, 1).daysInMonth, 29);
    });

    test('formats a Persian range without repeating month', () {
      expect(
        formatPersianDateRange(DateTime(2025, 1, 21), DateTime(2025, 2, 8)),
        '۲ تا ۲۰ بهمن ۱۴۰۳',
      );
    });
  });

  group('Scheduled campaign', () {
    final campaign = ScheduledCampaign(
      id: 'campaign-1',
      title: 'روز مربی',
      message: 'روزتان مبارک',
      audience: CampaignAudience.selected,
      selectedRecipients: const [
        CampaignRecipient(
          contactId: '1',
          name: 'مخاطب اول',
          phone: '09120000001',
        ),
      ],
      startDate: DateTime(2026, 10, 26),
      endDate: DateTime(2026, 10, 28),
      dailyStartMinute: 6 * 60,
      dailyEndMinute: 22 * 60,
      intervalSeconds: 30,
      createdAt: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 10, 20),
    );

    test('persists definition and recipient snapshots', () {
      final restored = ScheduledCampaign.fromJson(campaign.toJson());

      expect(restored.title, 'روز مربی');
      expect(restored.startDate, DateTime(2026, 10, 26));
      expect(restored.endsAt, DateTime(2026, 10, 28, 22));
      expect(restored.selectedRecipients.single.phone, '09120000001');
      expect(restored.state, ScheduledCampaignState.waiting);
    });

    test('finds the next legal daily send time', () {
      expect(
        campaign.nextAllowedAt(DateTime(2026, 10, 25, 18)),
        DateTime(2026, 10, 26, 6),
      );
      expect(
        campaign.nextAllowedAt(DateTime(2026, 10, 26, 5, 30)),
        DateTime(2026, 10, 26, 6),
      );
      final inside = DateTime(2026, 10, 26, 12, 15);
      expect(campaign.nextAllowedAt(inside), inside);
      expect(
        campaign.nextAllowedAt(DateTime(2026, 10, 26, 22, 1)),
        DateTime(2026, 10, 27, 6),
      );
      expect(campaign.nextAllowedAt(DateTime(2026, 10, 28, 22)), isNull);
    });

    test('runtime helper pauses at night and resumes next day', () {
      expect(
        nextAllowedCampaignTime(
          now: DateTime(2026, 10, 26, 22, 0),
          startsAt: campaign.startsAt,
          endsAt: campaign.endsAt,
          dailyStartMinute: campaign.dailyStartMinute,
          dailyEndMinute: campaign.dailyEndMinute,
        ),
        DateTime(2026, 10, 27, 6),
      );
    });

    test('editing locks when the start date arrives', () {
      expect(campaign.canEditAt(DateTime(2026, 10, 25, 23, 59)), isTrue);
      expect(campaign.canEditAt(DateTime(2026, 10, 26, 0, 0)), isFalse);
    });

    test('detects overlapping campaign windows', () {
      final overlapping = ScheduledCampaign.fromJson({
        ...campaign.toJson(),
        'id': 'campaign-2',
        'startDate': DateTime(2026, 10, 28).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 10, 29).millisecondsSinceEpoch,
        'dailyStartMinute': 21 * 60,
        'dailyEndMinute': 23 * 60,
      });
      final separateHours = ScheduledCampaign.fromJson({
        ...campaign.toJson(),
        'id': 'campaign-3',
        'dailyStartMinute': 22 * 60,
        'dailyEndMinute': 23 * 60,
      });

      expect(scheduledCampaignsOverlap(campaign, overlapping), isTrue);
      expect(scheduledCampaignsOverlap(campaign, separateHours), isFalse);
    });
  });
}
