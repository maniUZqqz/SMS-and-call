import 'package:flutter_test/flutter_test.dart';
import 'package:sms_and_call/features/campaigns/domain/scheduled_campaign.dart';

ScheduledCampaign _campaign({
  DateTime? start,
  DateTime? end,
  int startMinute = 8 * 60,
  int endMinute = 20 * 60,
}) {
  return ScheduledCampaign(
    id: 'c1',
    title: 'تست',
    message: 'سلام',
    audience: CampaignAudience.allAtStart,
    startDate: start ?? DateTime(2026, 11, 5),
    endDate: end ?? DateTime(2026, 11, 7),
    dailyStartMinute: startMinute,
    dailyEndMinute: endMinute,
    intervalSeconds: 30,
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );
}

void main() {
  group('calendar dates are stored as a calendar day, not an instant', () {
    // پیش از اصلاح، تاریخ شروع/پایان به‌صورت «میلی‌ثانیه‌ی نیمه‌شبِ محلی» ذخیره می‌شد.
    // اگر منطقه‌ی زمانی گوشی بین ذخیره و خواندن عوض می‌شد (سفر، تنظیم خودکار منطقه،
    // tzdata قدیمیِ ایران با ساعت تابستانی) تاریخ یک روز جابه‌جا می‌شد و کمپین یک
    // روز زودتر/دیرتر اجرا یا «بازه تمام شد» ثبت می‌شد.
    test('toJson writes yyyy-MM-dd', () {
      final json = _campaign().toJson();
      expect(json['startDate'], '2026-11-05');
      expect(json['endDate'], '2026-11-07');
    });

    test('round-trips independent of the time zone', () {
      final restored = ScheduledCampaign.fromJson(_campaign().toJson());
      expect(restored.startDate, DateTime(2026, 11, 5));
      expect(restored.endDate, DateTime(2026, 11, 7));
      expect(restored.startsAt, DateTime(2026, 11, 5, 8));
      expect(restored.endsAt, DateTime(2026, 11, 7, 20));
    });

    test('old epoch-millisecond data is still readable', () {
      final json = _campaign().toJson()
        ..['startDate'] = DateTime(2026, 11, 5).millisecondsSinceEpoch
        ..['endDate'] = DateTime(2026, 11, 7).millisecondsSinceEpoch;
      final restored = ScheduledCampaign.fromJson(json);
      expect(restored.startDate, DateTime(2026, 11, 5));
      expect(restored.endDate, DateTime(2026, 11, 7));
    });
  });

  group('window arithmetic', () {
    test('daily start is wall-clock time (no 24h arithmetic)', () {
      final campaign = _campaign();
      expect(
        campaign.nextAllowedAt(DateTime(2026, 11, 5, 21)),
        DateTime(2026, 11, 6, 8),
      );
      expect(nextCalendarDay(DateTime(2026, 3, 31, 23, 59)), DateTime(2026, 4, 1));
      expect(nextCalendarDay(DateTime(2026, 12, 31)), DateTime(2027, 1, 1));
    });

    test('the campaign is exactly over at endDate + daily end', () {
      final campaign = _campaign();
      expect(campaign.nextAllowedAt(DateTime(2026, 11, 7, 19, 59)), isNotNull);
      expect(campaign.nextAllowedAt(DateTime(2026, 11, 7, 20)), isNull);
    });
  });
}
