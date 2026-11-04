import 'package:untitled3/features/contacts/domain/contact.dart';

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
    );
  }

  SmsCampaign copyWith({
    int? nextIndex,
    int? sentCount,
    int? failedCount,
    List<String>? sentRecipientIds,
    List<String>? failedRecipientIds,
  }) {
    return SmsCampaign(
      id: id,
      message: message,
      recipients: recipients,
      intervalSeconds: intervalSeconds,
      startsAt: startsAt,
      endsAt: endsAt,
      title: title,
      scheduledCampaignId: scheduledCampaignId,
      dailyStartMinute: dailyStartMinute,
      dailyEndMinute: dailyEndMinute,
      nextIndex: nextIndex ?? this.nextIndex,
      sentCount: sentCount ?? this.sentCount,
      failedCount: failedCount ?? this.failedCount,
      sentRecipientIds: sentRecipientIds ?? this.sentRecipientIds,
      failedRecipientIds: failedRecipientIds ?? this.failedRecipientIds,
    );
  }

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
    final attempted = {...sentRecipientIds, ...failedRecipientIds};
    return recipients
        .where((item) => !attempted.contains(item.contactId))
        .toList();
  }
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
