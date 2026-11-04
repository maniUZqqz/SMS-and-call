class Contact {
  const Contact({
    required this.id,
    required this.name,
    required this.phone,
    this.note = '',
    this.addedAt,
  });

  final String id;
  final String name;
  final String phone;
  final String note;
  final DateTime? addedAt;

  factory Contact.create({
    required String name,
    required String phone,
    String note = '',
    DateTime? addedAt,
  }) {
    final createdAt = addedAt ?? DateTime.now();
    return Contact(
      id: createdAt.microsecondsSinceEpoch.toString(),
      name: name.trim(),
      phone: normalizePhoneNumber(phone),
      note: note.trim(),
      addedAt: createdAt,
    );
  }

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      addedAt: _readContactDate(json['addedAt']),
    );
  }

  Contact copyWith({String? name, String? phone, String? note}) {
    return Contact(
      id: id,
      name: name?.trim() ?? this.name,
      phone: phone == null ? this.phone : normalizePhoneNumber(phone),
      note: note?.trim() ?? this.note,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'note': note,
    'addedAt': effectiveAddedAt.millisecondsSinceEpoch,
  };

  DateTime get effectiveAddedAt {
    final stored = addedAt;
    if (stored != null) return stored;
    final micros = int.tryParse(id);
    if (micros != null && micros > 0) {
      return DateTime.fromMicrosecondsSinceEpoch(micros);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return _firstCharacter(parts.first);
    return '${_firstCharacter(parts.first)}${_firstCharacter(parts.last)}';
  }
}

DateTime? _readContactDate(dynamic value) {
  if (value is num && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _firstCharacter(String value) => String.fromCharCode(value.runes.first);

String normalizeContactSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ى', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool contactMatchesSearch(Contact contact, String query) {
  final normalizedQuery = normalizeContactSearch(query);
  if (normalizedQuery.isEmpty) return true;
  final normalizedPhoneQuery = normalizePhoneNumber(query);
  return normalizeContactSearch(contact.name).contains(normalizedQuery) ||
      (normalizedPhoneQuery.isNotEmpty &&
          contact.phone.contains(normalizedPhoneQuery));
}

String normalizePhoneNumber(String value) {
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  var normalized = value.trim();
  for (var index = 0; index < 10; index++) {
    normalized = normalized
        .replaceAll(persianDigits[index], '$index')
        .replaceAll(arabicDigits[index], '$index');
  }
  final hasPlus = normalized.startsWith('+');
  normalized = normalized.replaceAll(RegExp(r'\D'), '');
  return hasPlus ? '+$normalized' : normalized;
}

bool isValidPhoneNumber(String value) {
  final normalized = normalizePhoneNumber(value);
  return RegExp(r'^\+?\d{5,15}$').hasMatch(normalized);
}
