import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/core/constants/app_constants.dart';

class ServerConfig {
  String baseUrl;
  String otpPath;
  String markSentPath;

  /// متنی که قبل از کد در پیامک می‌آید. اگر شامل {code} باشد، کد دقیقاً همان‌جا قرار می‌گیرد.
  String smsTemplate;

  /// -1 = سیم‌کارت پیش‌فرض پیامک گوشی
  int simSubscriptionId;
  int simSlot;
  String simLabel;

  ServerConfig({
    required this.baseUrl,
    required this.otpPath,
    required this.markSentPath,
    this.smsTemplate = kDefaultTemplate,
    this.simSubscriptionId = -1,
    this.simSlot = -1,
    this.simLabel = '',
  });

  factory ServerConfig.defaults() => ServerConfig(
    baseUrl: 'http://192.168.43.47:5000',
    otpPath: '/api/next-otp',
    markSentPath: '/api/mark-sent',
  );

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    final d = ServerConfig.defaults();
    final base = (json['baseUrl'] as String?)?.trim();
    final otp = (json['otpPath'] as String?)?.trim();
    final mark = (json['markSentPath'] as String?)?.trim();
    final tpl = json['smsTemplate'];
    final sub = json['simSubscriptionId'];
    final slot = json['simSlot'];
    final label = json['simLabel'];
    return ServerConfig(
      baseUrl: (base != null && base.isNotEmpty) ? base : d.baseUrl,
      otpPath: (otp != null && otp.isNotEmpty) ? otp : d.otpPath,
      markSentPath: (mark != null && mark.isNotEmpty) ? mark : d.markSentPath,
      smsTemplate: tpl is String ? tpl : d.smsTemplate,
      simSubscriptionId: sub is num ? sub.toInt() : -1,
      simSlot: slot is num ? slot.toInt() : -1,
      simLabel: label is String ? label : '',
    );
  }

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'otpPath': otpPath,
    'markSentPath': markSentPath,
    'smsTemplate': smsTemplate,
    'simSubscriptionId': simSubscriptionId,
    'simSlot': simSlot,
    'simLabel': simLabel,
  };

  ServerConfig copyWith({
    String? baseUrl,
    String? otpPath,
    String? markSentPath,
    String? smsTemplate,
    int? simSubscriptionId,
    int? simSlot,
    String? simLabel,
  }) => ServerConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    otpPath: otpPath ?? this.otpPath,
    markSentPath: markSentPath ?? this.markSentPath,
    smsTemplate: smsTemplate ?? this.smsTemplate,
    simSubscriptionId: simSubscriptionId ?? this.simSubscriptionId,
    simSlot: simSlot ?? this.simSlot,
    simLabel: simLabel ?? this.simLabel,
  );

  /// متن نهایی پیامک
  String buildMessage(String code) {
    final t = smsTemplate;
    if (t.contains('{code}')) return t.replaceAll('{code}', code);
    if (t.trim().isEmpty) return code;
    final sep = RegExp(r'\s$').hasMatch(t) ? '' : ' ';
    return '$t$sep$code';
  }

  String get previewMessage => buildMessage('••••').replaceAll('\n', ' ⏎ ');

  String get simTitle => simSubscriptionId < 0
      ? 'پیش‌فرض گوشی'
      : (simLabel.isEmpty ? 'سیم‌کارت انتخاب‌شده' : simLabel);

  String get _cleanBase => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  String get _cleanOtpPath => otpPath.startsWith('/') ? otpPath : '/$otpPath';
  String get _cleanMarkSentPath =>
      markSentPath.startsWith('/') ? markSentPath : '/$markSentPath';

  Uri get otpUri => Uri.parse('$_cleanBase$_cleanOtpPath');
  Uri get markSentUri => Uri.parse('$_cleanBase$_cleanMarkSentPath');
}

/// انتخاب شناسه‌ی اشتراک (subId) برای ارسال.
/// - سیم انتخاب‌شده فعال است → همان
/// - شناسه عوض شده ولی همان اسلات هست → شناسه‌ی جدید همان اسلات
/// - «پیش‌فرض» و گوشی پیش‌فرض پیامک ندارد (حالت «هر بار بپرس») → اولین سیم فعال
int pickSubId(ServerConfig cfg, SimQuery q) {
  final want = cfg.simSubscriptionId;
  if (!q.permissionGranted) return want;
  if (want >= 0) {
    if (q.sims.any((s) => s.subscriptionId == want)) return want;
    if (cfg.simSlot >= 0) {
      for (final s in q.sims) {
        if (s.slot == cfg.simSlot) return s.subscriptionId;
      }
    }
    return want; // لایه بومی خطای «سیم فعال نیست» می‌دهد
  }
  if (q.defaultSmsSubId >= 0 &&
      q.sims.any((s) => s.subscriptionId == q.defaultSmsSubId)) {
    return q.defaultSmsSubId;
  }
  if (q.sims.isNotEmpty) return q.sims.first.subscriptionId;
  return -1;
}

String simNameOf(List<SimCard> sims, int subId) {
  for (final s in sims) {
    if (s.subscriptionId == subId) return s.title;
  }
  return 'سیم‌کارت پیش‌فرض';
}
