import 'package:sms_and_call/features/contacts/domain/contact.dart';

enum CampaignState {
  queued,
  waiting,
  sending,
  completed,
  cancelled,
  windowEnded,
  failed,
}

class CampaignRecipient {
  const CampaignRecipient({
    required this.contactId,
    required this.name,
    required this.phone,
  });

  final String contactId;
  final String name;
  final String phone;

  factory CampaignRecipient.fromContact(Contact contact) {
    return CampaignRecipient(
      contactId: contact.id,
      name: contact.name,
      phone: contact.phone,
    );
  }

  factory CampaignRecipient.fromJson(Map<String, dynamic> json) {
    return CampaignRecipient(
      contactId: (json['contactId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'contactId': contactId,
    'name': name,
    'phone': phone,
  };
}

class SmsCampaign {
  const SmsCampaign({
    required this.id,
    required this.message,
    required this.recipients,
    required this.intervalSeconds,
    required this.startsAt,
    required this.endsAt,
    this.title,
    this.scheduledCampaignId,
    this.dailyStartMinute,
    this.dailyEndMinute,
    this.nextIndex = 0,
    this.sentCount = 0,
    this.failedCount = 0,
    this.sentRecipientIds = const [],
    this.failedRecipientIds = const [],
    this.skipped = const {},
    this.failureNotes = const {},
    this.inFlightIndex = -1,
    this.attempt = 0,
    this.notBefore,
  });

  final String id;
  final String message;
  final List<CampaignRecipient> recipients;
  final int intervalSeconds;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? title;
  final String? scheduledCampaignId;
  final int? dailyStartMinute;
  final int? dailyEndMinute;
  final int nextIndex;
  final int sentCount;
  final int failedCount;
  final List<String> sentRecipientIds;
  final List<String> failedRecipientIds;

  /// گیرنده‌هایی که عمداً پیامک نگرفتند: contactId ← دلیل (`optout`، `duplicate`، `invalid`).
  final Map<String, String> skipped;

  /// توضیح کوتاهِ شکست هر گیرنده: contactId ← متن.
  final Map<String, String> failureNotes;

  /// اندیسِ گیرنده‌ای که درخواست ارسالش داده شده ولی نتیجه‌اش هنوز ثبت نشده.
  /// اگر برنامه وسط ارسال بمیرد، با همین مقدار می‌فهمیم نتیجه نامعلوم است و دوباره نمی‌فرستیم.
  final int inFlightIndex;

  /// چندمین تلاش برای گیرنده‌ی فعلی (۰ = هنوز تلاشی نشده).
  final int attempt;

  /// پیش از این زمان پیامک بعدی نباید برود (فاصله‌ی بین پیام‌ها، backoff، سقف ساعتی).
  final DateTime? notBefore;

  factory SmsCampaign.create({
    required String message,
    required List<Contact> contacts,
    required int intervalSeconds,
    required DateTime startsAt,
    required DateTime endsAt,
  }) {
    return SmsCampaign(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      message: message.trim(),
      recipients: contacts.map(CampaignRecipient.fromContact).toList(),
      intervalSeconds: intervalSeconds,
      startsAt: startsAt,
      endsAt: endsAt,
    );
  }

  factory SmsCampaign.fromJson(Map<String, dynamic> json) {
    final rawRecipients = json['recipients'];
    final recipients = rawRecipients is List
        ? rawRecipients
              .whereType<Map>()
              .map(
                (item) =>
                    CampaignRecipient.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <CampaignRecipient>[];
    final sentCount = (json['sentCount'] as num?)?.toInt() ?? 0;
    final failedCount = (json['failedCount'] as num?)?.toInt() ?? 0;
    var sentIds = _readStringList(json['sentRecipientIds']);
    var failedIds = _readStringList(json['failedRecipientIds']);
    if (sentIds.isEmpty && failedIds.isEmpty && (sentCount + failedCount) > 0) {
      sentIds = recipients
          .take(sentCount)
          .map((recipient) => recipient.contactId)
          .toList();
      failedIds = recipients
          .skip(sentCount)
          .take(failedCount)
          .map((recipient) => recipient.contactId)
          .toList();
    }
    return SmsCampaign(
      id: (json['id'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      recipients: recipients,
      intervalSeconds: (json['intervalSeconds'] as num?)?.toInt() ?? 0,
      startsAt: DateTime.fromMillisecondsSinceEpoch(
        (json['startsAt'] as num?)?.toInt() ?? 0,
      ),
      endsAt: DateTime.fromMillisecondsSinceEpoch(
        (json['endsAt'] as num?)?.toInt() ?? 0,
      ),
      title: json['title']?.toString(),
      scheduledCampaignId: json['scheduledCampaignId']?.toString(),
      dailyStartMinute: (json['dailyStartMinute'] as num?)?.toInt(),
      dailyEndMinute: (json['dailyEndMinute'] as num?)?.toInt(),
      nextIndex: (json['nextIndex'] as num?)?.toInt() ?? 0,
      sentCount: sentCount,
      failedCount: failedCount,
      sentRecipientIds: sentIds,
      failedRecipientIds: failedIds,
      skipped: _readStringMap(json['skipped']),
      failureNotes: _readStringMap(json['failureNotes']),
      inFlightIndex: (json['inFlightIndex'] as num?)?.toInt() ?? -1,
      attempt: (json['attempt'] as num?)?.toInt() ?? 0,
      notBefore: _readOptionalMillis(json['notBefore']),
    );
  }

  SmsCampaign copyWith({
    int? nextIndex,
    int? sentCount,
    int? failedCount,
    List<String>? sentRecipientIds,
    List<String>? failedRecipientIds,
    Map<String, String>? skipped,
    Map<String, String>? failureNotes,
    int? inFlightIndex,
    int? attempt,
    DateTime? notBefore,
    bool clearNotBefore = false,
    DateTime? startsAt,
    DateTime? endsAt,
  }) {
    return SmsCampaign(
      id: id,
      message: message,
      recipients: recipients,
      intervalSeconds: intervalSeconds,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      title: title,
      scheduledCampaignId: scheduledCampaignId,
      dailyStartMinute: dailyStartMinute,
      dailyEndMinute: dailyEndMinute,
      nextIndex: nextIndex ?? this.nextIndex,
      sentCount: sentCount ?? this.sentCount,
      failedCount: failedCount ?? this.failedCount,
      sentRecipientIds: sentRecipientIds ?? this.sentRecipientIds,
      failedRecipientIds: failedRecipientIds ?? this.failedRecipientIds,
      skipped: skipped ?? this.skipped,
      failureNotes: failureNotes ?? this.failureNotes,
      inFlightIndex: inFlightIndex ?? this.inFlightIndex,
      attempt: attempt ?? this.attempt,
      notBefore: clearNotBefore ? null : (notBefore ?? this.notBefore),
    );
  }

  /// اگر سرویس وسط ارسال یک پیامک کشته شده باشد، نتیجه‌اش نامعلوم است: ممکن است رفته باشد.
  /// برای جلوگیری از پیامک تکراری برای مشتری، آن گیرنده «ناموفق (نامعلوم)» ثبت می‌شود و می‌گذریم.
  SmsCampaign resolveInterrupted() {
    final index = inFlightIndex;
    if (index < 0) return this;
    if (index != nextIndex || index >= recipients.length) {
      return copyWith(inFlightIndex: -1);
    }
    final recipient = recipients[index];
    return copyWith(
      nextIndex: index + 1,
      failedCount: failedCount + 1,
      failedRecipientIds: [...failedRecipientIds, recipient.contactId],
      failureNotes: {
        ...failureNotes,
        recipient.contactId:
            'برنامه هنگام ارسال متوقف شد؛ نتیجه نامعلوم است و برای جلوگیری از پیامک تکراری دوباره ارسال نشد.',
      },
      inFlightIndex: -1,
      attempt: 0,
    );
  }

  int get skippedCount => skipped.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'message': message,
    'recipients': recipients.map((recipient) => recipient.toJson()).toList(),
    'intervalSeconds': intervalSeconds,
    'startsAt': startsAt.millisecondsSinceEpoch,
    'endsAt': endsAt.millisecondsSinceEpoch,
    if (title != null) 'title': title,
    if (scheduledCampaignId != null) 'scheduledCampaignId': scheduledCampaignId,
    if (dailyStartMinute != null) 'dailyStartMinute': dailyStartMinute,
    if (dailyEndMinute != null) 'dailyEndMinute': dailyEndMinute,
    'nextIndex': nextIndex,
    'sentCount': sentCount,
    'failedCount': failedCount,
    'sentRecipientIds': sentRecipientIds,
    'failedRecipientIds': failedRecipientIds,
    if (skipped.isNotEmpty) 'skipped': skipped,
    if (failureNotes.isNotEmpty) 'failureNotes': failureNotes,
    if (inFlightIndex >= 0) 'inFlightIndex': inFlightIndex,
    if (attempt > 0) 'attempt': attempt,
    if (notBefore != null) 'notBefore': notBefore!.millisecondsSinceEpoch,
  };

  int get totalCount => recipients.length;
  int get remainingCount => totalCount - nextIndex;
  CampaignRecipient? get nextRecipient =>
      nextIndex >= 0 && nextIndex < recipients.length
      ? recipients[nextIndex]
      : null;
}

class CampaignHistory {
  const CampaignHistory({
    required this.id,
    required this.message,
    required this.requestedCount,
    required this.sentCount,
    required this.failedCount,
    required this.startsAt,
    required this.endsAt,
    required this.finishedAt,
    required this.state,
    this.title,
    this.scheduledCampaignId,
    this.dailyStartMinute,
    this.dailyEndMinute,
    this.recipients = const [],
    this.sentRecipientIds = const [],
    this.failedRecipientIds = const [],
    this.skipped = const {},
    this.failureNotes = const {},
  });

  final String id;
  final String message;
  final int requestedCount;
  final int sentCount;
  final int failedCount;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime finishedAt;
  final CampaignState state;
  final String? title;
  final String? scheduledCampaignId;
  final int? dailyStartMinute;
  final int? dailyEndMinute;
  final List<CampaignRecipient> recipients;
  final List<String> sentRecipientIds;
  final List<String> failedRecipientIds;
  final Map<String, String> skipped;
  final Map<String, String> failureNotes;

  factory CampaignHistory.fromCampaign(
    SmsCampaign campaign,
    CampaignState state,
  ) {
    return CampaignHistory(
      id: campaign.id,
      message: campaign.message,
      requestedCount: campaign.totalCount,
      sentCount: campaign.sentCount,
      failedCount: campaign.failedCount,
      startsAt: campaign.startsAt,
      endsAt: campaign.endsAt,
      finishedAt: DateTime.now(),
      state: state,
      title: campaign.title,
      scheduledCampaignId: campaign.scheduledCampaignId,
      dailyStartMinute: campaign.dailyStartMinute,
      dailyEndMinute: campaign.dailyEndMinute,
      recipients: campaign.recipients,
      sentRecipientIds: campaign.sentRecipientIds,
      failedRecipientIds: campaign.failedRecipientIds,
      skipped: campaign.skipped,
      failureNotes: campaign.failureNotes,
    );
  }

  factory CampaignHistory.fromJson(Map<String, dynamic> json) {
    final rawState = (json['state'] ?? '').toString();
    return CampaignHistory(
      id: (json['id'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      requestedCount: (json['requestedCount'] as num?)?.toInt() ?? 0,
      sentCount: (json['sentCount'] as num?)?.toInt() ?? 0,
      failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
      startsAt: DateTime.fromMillisecondsSinceEpoch(
        (json['startsAt'] as num?)?.toInt() ?? 0,
      ),
      endsAt: DateTime.fromMillisecondsSinceEpoch(
        (json['endsAt'] as num?)?.toInt() ?? 0,
      ),
      finishedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['finishedAt'] as num?)?.toInt() ?? 0,
      ),
      state: CampaignState.values.firstWhere(
        (value) => value.name == rawState,
        orElse: () => CampaignState.failed,
      ),
      title: json['title']?.toString(),
      scheduledCampaignId: json['scheduledCampaignId']?.toString(),
      dailyStartMinute: (json['dailyStartMinute'] as num?)?.toInt(),
      dailyEndMinute: (json['dailyEndMinute'] as num?)?.toInt(),
      recipients: _readRecipients(json['recipients']),
      sentRecipientIds: _readStringList(json['sentRecipientIds']),
      failedRecipientIds: _readStringList(json['failedRecipientIds']),
      skipped: _readStringMap(json['skipped']),
      failureNotes: _readStringMap(json['failureNotes']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'message': message,
    'requestedCount': requestedCount,
    'sentCount': sentCount,
    'failedCount': failedCount,
    'startsAt': startsAt.millisecondsSinceEpoch,
    'endsAt': endsAt.millisecondsSinceEpoch,
    'finishedAt': finishedAt.millisecondsSinceEpoch,
    'state': state.name,
    if (title != null) 'title': title,
    if (scheduledCampaignId != null) 'scheduledCampaignId': scheduledCampaignId,
    if (dailyStartMinute != null) 'dailyStartMinute': dailyStartMinute,
    if (dailyEndMinute != null) 'dailyEndMinute': dailyEndMinute,
    'recipients': recipients.map((recipient) => recipient.toJson()).toList(),
    'sentRecipientIds': sentRecipientIds,
    'failedRecipientIds': failedRecipientIds,
    if (skipped.isNotEmpty) 'skipped': skipped,
    if (failureNotes.isNotEmpty) 'failureNotes': failureNotes,
  };

  List<CampaignRecipient> get sentRecipients {
    final ids = sentRecipientIds.toSet();
    return recipients.where((item) => ids.contains(item.contactId)).toList();
  }

  List<CampaignRecipient> get failedRecipients {
    final ids = failedRecipientIds.toSet();
    return recipients.where((item) => ids.contains(item.contactId)).toList();
  }

  List<CampaignRecipient> get unattemptedRecipients {
    final attempted = {
      ...sentRecipientIds,
      ...failedRecipientIds,
      ...skipped.keys,
    };
    return recipients
        .where((item) => !attempted.contains(item.contactId))
        .toList();
  }

  /// گیرنده‌هایی که عمداً رد شدند (فهرست لغو، شماره‌ی تکراری یا نامعتبر).
  List<CampaignRecipient> get skippedRecipients {
    return recipients
        .where((item) => skipped.containsKey(item.contactId))
        .toList();
  }
}

Map<String, String> _readStringMap(dynamic value) {
  if (value is! Map) return <String, String>{};
  return value.map((key, item) => MapEntry(key.toString(), item.toString()));
}

DateTime? _readOptionalMillis(dynamic value) {
  if (value is num && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

List<String> _readStringList(dynamic value) {
  if (value is! List) return <String>[];
  return value.map((item) => item.toString()).toList();
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

int campaignWindowCapacity({
  required DateTime startsAt,
  required DateTime endsAt,
  required int intervalSeconds,
}) {
  if (!endsAt.isAfter(startsAt)) return 0;
  if (intervalSeconds <= 0) return 1;
  final windowMicros = endsAt.difference(startsAt).inMicroseconds;
  final intervalMicros = Duration(seconds: intervalSeconds).inMicroseconds;
  return ((windowMicros - 1) ~/ intervalMicros) + 1;
}
