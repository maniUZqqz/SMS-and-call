import 'package:sms_and_call/features/campaigns/domain/scheduled_campaign.dart';

/// چرا باید سرویس در یک لحظه بیدار شود.
enum WakeReason { sendWindow, expiry }

class PlannedWake {
  const PlannedWake(this.at, this.reason);

  final DateTime at;
  final WakeReason reason;

  @override
  String toString() => 'PlannedWake($at, ${reason.name})';
}

/// نزدیک‌ترین لحظه‌ای که یکی از کمپین‌های زمان‌بندی‌شده کاری برای انجام دارد، یا null
/// اگر هیچ کمپین فعالی نیست. همین لحظه به آلارمِ سیستم‌عامل داده می‌شود تا حتی وقتی
/// فرایند برنامه کشته شده یا گوشی در حالت Doze است، سرویس بیدار شود.
///
/// - کمپینی که الان در بازه‌ی مجاز است ← همین حالا.
/// - کمپینی که منتظر شروع یا شروعِ فردا است ← آن لحظه.
/// - کمپینی که بازه‌اش تمام شده ولی هنوز «پایان‌یافته» ثبت نشده ← همین حالا (برای ثبت).
/// - لحظه‌ی پایان هر کمپین هم یک نقطه‌ی بیداری است تا وضعیتش درست بسته شود.
PlannedWake? planNextWake(Iterable<ScheduledCampaign> campaigns, DateTime now) {
  PlannedWake? best;
  void consider(DateTime at, WakeReason reason) {
    final effective = at.isBefore(now) ? now : at;
    final current = best;
    if (current == null || effective.isBefore(current.at)) {
      best = PlannedWake(effective, reason);
    }
  }

  for (final campaign in campaigns) {
    if (campaign.isTerminal) continue;
    if (!now.isBefore(campaign.endsAt)) {
      consider(now, WakeReason.expiry);
      continue;
    }
    final allowed = campaign.nextActionAt(now);
    if (allowed != null) consider(allowed, WakeReason.sendWindow);
    consider(campaign.endsAt, WakeReason.expiry);
  }
  return best;
}

/// کمپین‌هایی که همین الان باید شروع (یا ادامه) پیدا کنند، به ترتیب زمان شروع.
List<ScheduledCampaign> dueCampaigns(
  Iterable<ScheduledCampaign> campaigns,
  DateTime now,
) {
  final due = campaigns.where((campaign) {
    if (campaign.isTerminal) return false;
    final allowed = campaign.nextActionAt(now);
    return allowed != null && !allowed.isAfter(now);
  }).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return due;
}

/// کمپین‌هایی که بازه‌شان تمام شده و باید «پایان‌یافته (بازه تمام شد)» ثبت شوند.
List<ScheduledCampaign> expiredCampaigns(
  Iterable<ScheduledCampaign> campaigns,
  DateTime now,
) {
  return campaigns
      .where(
        (campaign) => !campaign.isTerminal && !now.isBefore(campaign.endsAt),
      )
      .toList();
}
