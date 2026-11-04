import 'package:sms_and_call/core/utils/persian_date.dart';
import 'package:sms_and_call/features/contacts/domain/sms_campaign.dart';

enum CampaignAudience { allAtStart, selected }

enum ScheduledCampaignState {
  waiting,
  sending,
  completed,
  windowEnded,
  failed,
  cancelled,
}

class ScheduledCampaign {
  const ScheduledCampaign({
    required this.id,
    required this.title,
    required this.message,
    required this.audience,
    required this.startDate,
    required this.endDate,
    required this.dailyStartMinute,
    required this.dailyEndMinute,
    required this.intervalSeconds,
    required this.createdAt,
    required this.updatedAt,
    this.selectedRecipients = const [],
    this.state = ScheduledCampaignState.waiting,
    this.execution,
    this.lastError,
  });

  final String id;
  final String title;
  final String message;
  final CampaignAudience audience;
  final List<CampaignRecipient> selectedRecipients;
  final DateTime startDate;
  final DateTime endDate;
  final int dailyStartMinute;
  final int dailyEndMinute;
  final int intervalSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ScheduledCampaignState state;
  final SmsCampaign? execution;
  final String? lastError;

  factory ScheduledCampaign.fromJson(Map<String, dynamic> json) {
    final rawAudience = (json['audience'] ?? '').toString();
    final rawState = (json['state'] ?? '').toString();
    final rawExecution = json['execution'];
    return ScheduledCampaign(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      audience: CampaignAudience.values.firstWhere(
        (value) => value.name == rawAudience,
        orElse: () => CampaignAudience.selected,
      ),
      selectedRecipients: _readRecipients(json['selectedRecipients']),
      startDate: _readDate(json['startDate']),
      endDate: _readDate(json['endDate']),
      dailyStartMinute: (json['dailyStartMinute'] as num?)?.toInt() ?? 0,
      dailyEndMinute: (json['dailyEndMinute'] as num?)?.toInt() ?? 0,
      intervalSeconds: (json['intervalSeconds'] as num?)?.toInt() ?? 0,
      createdAt: _readDateTime(json['createdAt']),
      updatedAt: _readDateTime(json['updatedAt']),
      state: ScheduledCampaignState.values.firstWhere(
        (value) => value.name == rawState,
        orElse: () => ScheduledCampaignState.waiting,
      ),
      execution: rawExecution is Map
          ? SmsCampaign.fromJson(Map<String, dynamic>.from(rawExecution))
          : null,
      lastError: json['lastError']?.toString(),
    );
  }

  ScheduledCampaign copyWith({
    String? title,
    String? message,
    CampaignAudience? audience,
    List<CampaignRecipient>? selectedRecipients,
    DateTime? startDate,
    DateTime? endDate,
    int? dailyStartMinute,
    int? dailyEndMinute,
    int? intervalSeconds,
    DateTime? updatedAt,
    ScheduledCampaignState? state,
    SmsCampaign? execution,
    bool clearExecution = false,
    String? lastError,
    bool clearLastError = false,
  }) {
    return ScheduledCampaign(
      id: id,
      title: title ?? this.title,
      message: message ?? this.message,
      audience: audience ?? this.audience,
      selectedRecipients: selectedRecipients ?? this.selectedRecipients,
      startDate: dateOnly(startDate ?? this.startDate),
      endDate: dateOnly(endDate ?? this.endDate),
      dailyStartMinute: dailyStartMinute ?? this.dailyStartMinute,
      dailyEndMinute: dailyEndMinute ?? this.dailyEndMinute,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      state: state ?? this.state,
      execution: clearExecution ? null : execution ?? this.execution,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'audience': audience.name,
    'selectedRecipients': selectedRecipients
        .map((recipient) => recipient.toJson())
        .toList(),
    // تاریخ تقویمی (بدون ساعت و منطقه‌ی زمانی) تا با تغییر timezone گوشی یک روز جابه‌جا نشود
    'startDate': formatIsoDate(startDate),
    'endDate': formatIsoDate(endDate),
    'dailyStartMinute': dailyStartMinute,
    'dailyEndMinute': dailyEndMinute,
    'intervalSeconds': intervalSeconds,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'state': state.name,
    if (execution != null) 'execution': execution!.toJson(),
    if (lastError != null) 'lastError': lastError,
  };

  DateTime get startsAt => _atMinute(startDate, dailyStartMinute);
  DateTime get endsAt => _atMinute(endDate, dailyEndMinute);

  bool get isTerminal => switch (state) {
    ScheduledCampaignState.completed ||
    ScheduledCampaignState.windowEnded ||
    ScheduledCampaignState.failed ||
    ScheduledCampaignState.cancelled => true,
    _ => false,
  };

  bool canEditAt(DateTime now) {
    return state == ScheduledCampaignState.waiting &&
        dateOnly(now).isBefore(dateOnly(startDate));
  }

  bool isInsideWindow(DateTime now) {
    if (now.isBefore(startsAt) || !now.isBefore(endsAt)) return false;
    final minute = now.hour * 60 + now.minute;
    return minute >= dailyStartMinute && minute < dailyEndMinute;
  }

  /// نزدیک‌ترین لحظه‌ای که این کمپین واقعاً کاری دارد: مثل [nextAllowedAt] ولی با احترام به
  /// «نه زودتر از» ذخیره‌شده در اجرا (فاصله بین پیامک‌ها، سقف ساعتی، مکثِ خطا). بدون این،
  /// کمپینِ در مکث همیشه «سررسید» به نظر می‌رسید و بی‌وقفه شروع و متوقف می‌شد.
  DateTime? nextActionAt(DateTime now) {
    final notBefore = execution?.notBefore;
    final from = notBefore != null && notBefore.isAfter(now) ? notBefore : now;
    return nextAllowedAt(from);
  }

  DateTime? nextAllowedAt(DateTime now) {
    if (!now.isBefore(endsAt)) return null;
    if (now.isBefore(startsAt)) return startsAt;
    final today = dateOnly(now);
    if (today.isBefore(startDate)) return startsAt;
    if (today.isAfter(endDate)) return null;

    final minute = now.hour * 60 + now.minute;
    if (minute < dailyStartMinute) {
      return _atMinute(today, dailyStartMinute);
    }
    if (minute < dailyEndMinute) return now;

    final nextDay = nextCalendarDay(today);
    if (nextDay.isAfter(endDate)) return null;
    return _atMinute(nextDay, dailyStartMinute);
  }

  int get recipientCount => audience == CampaignAudience.allAtStart
      ? execution?.totalCount ?? 0
      : selectedRecipients.length;

  int get sentCount => execution?.sentCount ?? 0;
  int get failedCount => execution?.failedCount ?? 0;

  int get remainingCount {
    final runtime = execution;
    if (runtime != null) return runtime.remainingCount;
    return audience == CampaignAudience.selected
        ? selectedRecipients.length
        : 0;
  }
}

DateTime? nextAllowedCampaignTime({
  required DateTime now,
  required DateTime startsAt,
  required DateTime endsAt,
  int? dailyStartMinute,
  int? dailyEndMinute,
}) {
  if (!now.isBefore(endsAt)) return null;
  if (now.isBefore(startsAt)) return startsAt;
  if (dailyStartMinute == null || dailyEndMinute == null) return now;

  final minute = now.hour * 60 + now.minute;
  if (minute < dailyStartMinute) {
    final target = _atMinute(now, dailyStartMinute);
    return target.isBefore(endsAt) ? target : null;
  }
  if (minute < dailyEndMinute) return now;

  final nextDay = nextCalendarDay(now);
  final target = _atMinute(nextDay, dailyStartMinute);
  return target.isBefore(endsAt) ? target : null;
}

bool scheduledCampaignsOverlap(
  ScheduledCampaign first,
  ScheduledCampaign second,
) {
  if (first.isTerminal || second.isTerminal) return false;
  final datesOverlap =
      !first.endDate.isBefore(second.startDate) &&
      !second.endDate.isBefore(first.startDate);
  if (!datesOverlap) return false;
  return first.dailyStartMinute < second.dailyEndMinute &&
      second.dailyStartMinute < first.dailyEndMinute;
}

bool scheduledCampaignOverlapsRange(
  ScheduledCampaign campaign,
  DateTime startsAt,
  DateTime endsAt,
) {
  if (campaign.isTerminal || !endsAt.isAfter(startsAt)) return false;
  var day = dateOnly(startsAt);
  final lastDay = dateOnly(endsAt);
  while (!day.isAfter(lastDay)) {
    if (!day.isBefore(campaign.startDate) && !day.isAfter(campaign.endDate)) {
      final windowStart = _atMinute(day, campaign.dailyStartMinute);
      final windowEnd = _atMinute(day, campaign.dailyEndMinute);
      if (startsAt.isBefore(windowEnd) && endsAt.isAfter(windowStart)) {
        return true;
      }
    }
    day = nextCalendarDay(day);
  }
  return false;
}

/// ساعتِ دیواری «minute» دقیقه بعد از نیمه‌شب همان روز. از سازنده‌ی DateTime استفاده می‌شود
/// (نه جمع Duration) تا در روز تغییر ساعت تابستانی، ساعت ۸ همچنان ۸ بماند.
DateTime _atMinute(DateTime day, int minute) {
  return DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);
}

/// نیمه‌شبِ روز بعد (با ساختار تقویمی، نه جمع ۲۴ ساعت).
DateTime nextCalendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day + 1);

/// `yyyy-MM-dd`
String formatIsoDate(DateTime value) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}';
}

DateTime _readDate(dynamic value) {
  if (value is String) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    }
  }
  // قالب قدیمی: میلی‌ثانیه‌ی نیمه‌شبِ محلی
  return dateOnly(_readDateTime(value));
}

DateTime _readDateTime(dynamic value) {
  if (value is num && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

List<CampaignRecipient> _readRecipients(dynamic value) {
  if (value is! List) return <CampaignRecipient>[];
  return value
      .whereType<Map>()
      .map(
        (item) => CampaignRecipient.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList();
}
