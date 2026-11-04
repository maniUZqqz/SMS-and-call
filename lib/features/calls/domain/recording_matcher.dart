import 'package:sms_and_call/features/calls/domain/call_models.dart';
import 'package:sms_and_call/features/contacts/domain/contact.dart';

/// برندهایی که پوشه‌ی ضبط تماسشان شناخته شده است.
enum RecorderBrand {
  samsung,
  xiaomi,
  huawei,
  oppo,
  vivo,
  motorola,
  google,
  other,
}

/// برند گوشی را از رشته‌های `Build.MANUFACTURER/BRAND/MODEL` حدس می‌زند.
RecorderBrand detectRecorderBrand({
  String manufacturer = '',
  String brand = '',
  String model = '',
}) {
  final text = '$manufacturer $brand $model'.toLowerCase();
  bool any(List<String> keys) => keys.any(text.contains);
  if (any(['samsung'])) return RecorderBrand.samsung;
  if (any(['xiaomi', 'redmi', 'poco', 'blackshark'])) return RecorderBrand.xiaomi;
  if (any(['huawei', 'honor'])) return RecorderBrand.huawei;
  if (any(['oppo', 'realme', 'oneplus'])) return RecorderBrand.oppo;
  if (any(['vivo', 'iqoo'])) return RecorderBrand.vivo;
  if (any(['motorola', 'moto ', 'lenovo'])) return RecorderBrand.motorola;
  if (any(['google', 'pixel'])) return RecorderBrand.google;
  return RecorderBrand.other;
}

/// نتیجه‌ی تطبیق یک فایل صوتی با پوشه‌ی ضبط تماس.
class FolderMatch {
  const FolderMatch({
    required this.brand,
    required this.confidence,
    required this.reason,
  });

  /// برندی که این پوشه به آن تعلق دارد (یا [RecorderBrand.other] برای الگوی عمومی).
  final RecorderBrand brand;

  /// ۰ تا ۱؛ مقدار ≥ ۰٫۵ یعنی «حتماً ضبط تماس است».
  final double confidence;
  final String reason;

  bool get isConfident => confidence >= 0.5;
}

class _Rule {
  const _Rule(this.brand, this.fragments, {this.exactRoot = false});

  final RecorderBrand brand;

  /// قطعه‌های مسیر (با `/` و حروف کوچک)؛ هر کدام که داخل مسیر باشد تطبیق است.
  final List<String> fragments;

  /// مسیر باید دقیقاً با قطعه شروع شود (مثل `call/` در ریشه‌ی حافظه).
  final bool exactRoot;
}

const List<_Rule> _folderRules = [
  _Rule(RecorderBrand.samsung, ['recordings/call/', 'voice recorder/call']),
  _Rule(RecorderBrand.samsung, ['call/'], exactRoot: true),
  _Rule(RecorderBrand.xiaomi, [
    'miui/sound_recorder/call_rec/',
    'sound_recorder/call_rec/',
    'miui/sound_recorder/call/',
    'recordings/call_rec/',
  ]),
  _Rule(RecorderBrand.huawei, [
    'sounds/callrecord/',
    'record/callrecord/',
    'recordings/callrecord/',
    'huawei/callrecord/',
    'sounds/call recordings/',
  ]),
  _Rule(RecorderBrand.oppo, [
    'music/recordings/call recordings/',
    'recordings/call recordings/',
    'recordings/callrecordings/',
    'callrecordings/',
    'phonerecord/',
    'phone_record/',
    'record/phonerecord/',
  ]),
  _Rule(RecorderBrand.vivo, [
    'record/call/',
    'recordings/call/',
    'record/callrecord/',
  ]),
  _Rule(RecorderBrand.motorola, [
    'recordings/call recordings/',
    'callrecordings/',
    'call_recordings/',
  ]),
  _Rule(RecorderBrand.google, [
    'android/data/com.google.android.dialer/',
    'callrecordings/',
  ]),
];

/// الگوهای عمومی برای ضبط‌کننده‌های دیگر (ACR، Cube و …) و پوشه‌های ناشناخته.
final List<RegExp> _genericPathPatterns = [
  RegExp(r'call[ _-]?rec'),
  RegExp(r'rec(order|ording)s?[ _/-]*call'),
  RegExp(r'call[ _-]?record'),
  RegExp(r'phone[ _-]?record'),
  RegExp(r'acrcalls'),
  RegExp(r'تماس'),
];

String _normalizePath(String path) {
  var value = path.replaceAll('\\', '/').toLowerCase().trim();
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  if (value.isNotEmpty && !value.endsWith('/')) value = '$value/';
  return value;
}

final RegExp _audioExtensions = RegExp(
  r'\.(m4a|mp3|amr|awb|wav|aac|3gp|3ga|ogg|opus|flac|mp4|wma|mka)$',
  caseSensitive: false,
);

bool hasAudioExtension(String name) => _audioExtensions.hasMatch(name);

/// آیا فایلی با این مسیر نسبی و نام، ضبط تماسِ ضبط‌کننده‌ی گوشی است؟
/// `relativePath` مسیر پوشه نسبت به حافظه‌ی داخلی است (مثل `Recordings/Call/`).
FolderMatch? matchRecordingFolder({
  required String relativePath,
  required String displayName,
}) {
  if (displayName.isNotEmpty && !hasAudioExtension(displayName)) return null;
  final path = _normalizePath(relativePath);

  for (final rule in _folderRules) {
    for (final fragment in rule.fragments) {
      final hit = rule.exactRoot ? path.startsWith(fragment) : path.contains(fragment);
      if (hit) {
        return FolderMatch(
          brand: rule.brand,
          confidence: 0.95,
          reason: 'پوشه‌ی ضبط تماس ${rule.brand.name}: $fragment',
        );
      }
    }
  }

  for (final pattern in _genericPathPatterns) {
    if (pattern.hasMatch(path)) {
      return FolderMatch(
        brand: RecorderBrand.other,
        confidence: 0.7,
        reason: 'نام پوشه شبیه ضبط تماس است',
      );
    }
  }

  // فقط از روی نام فایل: «Call recording …»، «Call_0912…»، «تماس …»
  final name = displayName.toLowerCase();
  final nameLooksLikeCall =
      RegExp(r'^(call[ _-]?(rec|record|recording|with|from|to)?|rec[_-]?call|تماس)').hasMatch(name) ||
      name.contains('call recording') ||
      name.contains('callrecord');
  // نام‌هایی مثل «Call_me.mp3» (زنگ موبایل) نباید ضبط تماس حساب شوند: شماره یا واژه‌ی record لازم است
  final hasPhoneDigits = RegExp(r'\d{7,}').hasMatch(name);
  if (nameLooksLikeCall && (hasPhoneDigits || name.contains('record'))) {
    return FolderMatch(
      brand: RecorderBrand.other,
      confidence: 0.55,
      reason: 'نام فایل شبیه ضبط تماس است',
    );
  }
  return null;
}

/// اطلاعاتی که می‌شود از نام فایل ضبط درآورد.
class ParsedRecordingName {
  const ParsedRecordingName({this.number = '', this.name = '', this.when});

  final String number;
  final String name;

  /// زمان داخل نام فایل (محلی)، اگر پیدا شد.
  final DateTime? when;
}

/// نام فایل ضبط تماس را تجزیه می‌کند. مثال‌های پشتیبانی‌شده:
/// - سامسونگ: `Call recording Ali_231105_142530.m4a`، `Call recording 09123456789_231105_142530.m4a`
/// - شیائومی: `Ali(09123456789)_20231105142530.mp3`
/// - هواوی/آنر: `09123456789_20231105142530.amr`، `Ali_20231105142530.amr`
/// - اوپو/ریلمی/وان‌پلاس: `Call recording 09123456789_20231105_142530.m4a`
/// - عمومی: `Call_+989123456789_2023-11-05_14-25-30.wav`
ParsedRecordingName parseRecordingName(String displayName) {
  var base = displayName.trim();
  final dot = base.lastIndexOf('.');
  if (dot > 0 && hasAudioExtension(base)) base = base.substring(0, dot);

  DateTime? when;
  var remaining = base;

  // 20231105142530 یا 20231105_142530 یا 2023-11-05_14-25-30
  final longDate = RegExp(
    r'(20\d{2})[-_.]?(\d{2})[-_.]?(\d{2})[-_ T.]?(\d{2})[-_.:]?(\d{2})[-_.:]?(\d{2})',
  ).firstMatch(remaining);
  if (longDate != null) {
    when = _safeDate(
      int.parse(longDate.group(1)!),
      int.parse(longDate.group(2)!),
      int.parse(longDate.group(3)!),
      int.parse(longDate.group(4)!),
      int.parse(longDate.group(5)!),
      int.parse(longDate.group(6)!),
    );
    if (when != null) remaining = remaining.replaceRange(longDate.start, longDate.end, ' ');
  }
  if (when == null) {
    // سامسونگ: yymmdd_hhmmss
    final shortDate = RegExp(r'(?<!\d)(\d{2})(\d{2})(\d{2})[_-](\d{2})(\d{2})(\d{2})(?!\d)')
        .firstMatch(remaining);
    if (shortDate != null) {
      when = _safeDate(
        2000 + int.parse(shortDate.group(1)!),
        int.parse(shortDate.group(2)!),
        int.parse(shortDate.group(3)!),
        int.parse(shortDate.group(4)!),
        int.parse(shortDate.group(5)!),
        int.parse(shortDate.group(6)!),
      );
      if (when != null) {
        remaining = remaining.replaceRange(shortDate.start, shortDate.end, ' ');
      }
    }
  }

  // شماره: داخل پرانتز، یا یک دنباله‌ی ۷ تا ۱۵ رقمی (با + اختیاری)
  var number = '';
  final bracketed = RegExp(r'[(\[]\s*(\+?[\d۰-۹٠-٩ \-]{7,20})\s*[)\]]').firstMatch(remaining);
  if (bracketed != null) {
    number = normalizePhoneNumber(bracketed.group(1)!);
    remaining = remaining.replaceRange(bracketed.start, bracketed.end, ' ');
  } else {
    final plain = RegExp(r'(?<![\d])(\+?[\d۰-۹٠-٩]{7,15})(?![\d])').firstMatch(remaining);
    if (plain != null) {
      number = normalizePhoneNumber(plain.group(1)!);
      remaining = remaining.replaceRange(plain.start, plain.end, ' ');
    }
  }

  var name = remaining
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'call\s*-?\s*recording', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'call\s*-?\s*record', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'^\s*call\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  name = name.replaceAll(RegExp(r'^[\s\-–]+|[\s\-–]+$'), '');
  // اگر «نام» فقط ارقام/جداکننده بود، یعنی نامی نیست
  if (RegExp(r'^[\d\s\-+()]*$').hasMatch(name)) name = '';

  return ParsedRecordingName(number: number, name: name, when: when);
}

DateTime? _safeDate(int y, int mo, int d, int h, int mi, int s) {
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 59) {
    return null;
  }
  return DateTime(y, mo, d, h, mi, s);
}

/// نتیجه‌ی پیدا کردن تماسِ متناظر یک ضبط.
class CallMatch {
  const CallMatch(this.call, this.score);

  final CallLogEntry call;
  final double score;
}

/// ضبط را به یکی از تماس‌های تاریخچه وصل می‌کند.
///
/// [times] زمان‌های مربوط به فایل است (زمان افزودن، آخرین تغییر، زمان داخل نام).
/// ضبط‌کننده‌ها معمولاً فایل را بین شروع و کمی بعد از پایان تماس می‌نویسند.
/// اگر شماره از نام فایل معلوم باشد باید با شماره‌ی تماس بخواند.
CallMatch? findCallForRecording({
  required List<DateTime> times,
  required List<CallLogEntry> calls,
  String parsedNumber = '',
  Duration slack = const Duration(minutes: 3),
}) {
  if (times.isEmpty || calls.isEmpty) return null;
  final wantedKey = parsedNumber.isEmpty ? '' : phoneKey(parsedNumber);

  CallMatch? best;
  for (final call in calls) {
    if (call.duration <= Duration.zero) continue; // تماس بی‌پاسخ ضبط ندارد
    final callKey = phoneKey(call.number);
    final numberKnown = wantedKey.isNotEmpty && callKey.isNotEmpty;
    if (numberKnown && wantedKey != callKey) continue;

    final from = call.startedAt.subtract(const Duration(minutes: 1));
    final to = call.endedAt.add(slack);
    double? bestGap;
    for (final time in times) {
      final gap = time.isBefore(from)
          ? from.difference(time).inSeconds.toDouble()
          : time.isAfter(to)
          ? time.difference(to).inSeconds.toDouble()
          : 0.0;
      if (bestGap == null || gap < bestGap) bestGap = gap;
    }
    if (bestGap == null || bestGap > 120) continue;

    // نزدیکیِ پایان تماس به زمان فایل، امتیاز را دقیق‌تر می‌کند
    double endDistance = double.infinity;
    for (final time in times) {
      final distance = time.difference(call.endedAt).inSeconds.abs().toDouble();
      if (distance < endDistance) endDistance = distance;
    }
    var score = 100.0 - bestGap / 2 - (endDistance.isFinite ? endDistance / 30 : 0);
    if (numberKnown) score += 50;
    if (best == null || score > best.score) best = CallMatch(call, score);
  }
  return best;
}
