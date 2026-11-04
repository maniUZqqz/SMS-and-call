import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/core/theme/app_theme.dart';
import 'package:sms_and_call/features/calls/data/call_settings.dart';
import 'package:sms_and_call/features/calls/domain/brand_guide.dart';
import 'package:sms_and_call/features/calls/domain/recording_matcher.dart';
import 'package:sms_and_call/features/calls/presentation/call_format.dart';
import 'package:sms_and_call/features/calls/services/transcription.dart';

/// راه‌اندازی و تنظیمات ضبط تماس. اولین بار به‌صورت راهنمای مرحله‌به‌مرحله باز می‌شود.
class CallSetupPage extends StatefulWidget {
  const CallSetupPage({super.key});

  @override
  State<CallSetupPage> createState() => _CallSetupPageState();
}

class _CallSetupPageState extends State<CallSetupPage> with WidgetsBindingObserver {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _language = TextEditingController();
  final _apiKey = TextEditingController();
  final _uploadUrl = TextEditingController();
  final _uploadToken = TextEditingController();

  CallSettings _settings = const CallSettings();
  BridgeStatus _status = BridgeStatus.unknown;
  CallRecorderStatus _recorder = CallRecorderStatus.unknown;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _showKey = false;
  String? _testMessage;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [_baseUrl, _model, _language, _apiKey, _uploadUrl, _uploadToken]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshStatus());
  }

  Future<void> _load() async {
    final settings = await CallSettingsStorage.load();
    final key = await CallSecrets.readSttKey();
    final token = await CallSecrets.readUploadToken();
    final status = await SmsBridge.status();
    final recorder = await SmsBridge.callRecorderStatus();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _baseUrl.text = settings.sttBaseUrl;
      _model.text = settings.sttModel;
      _language.text = settings.language;
      _apiKey.text = key;
      _uploadUrl.text = settings.uploadUrl;
      _uploadToken.text = token;
      _status = status;
      _recorder = recorder;
      _loading = false;
    });
  }

  Future<void> _refreshStatus() async {
    final status = await SmsBridge.status();
    final recorder = await SmsBridge.callRecorderStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _recorder = recorder;
    });
  }

  RecorderBrand get _brand => detectRecorderBrand(
    manufacturer: _status.manufacturer,
    brand: _status.brand,
    model: _status.model,
  );

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _acceptConsent() async {
    setState(() => _settings = _settings.copyWith(consentAcceptedAt: DateTime.now()));
    await CallSettingsStorage.update((s) => s.copyWith(consentAcceptedAt: DateTime.now()));
  }

  Future<void> _request(Permission permission) async {
    try {
      await permission.request();
    } catch (_) {}
    await _refreshStatus();
    if (!mounted) return;
    final granted = await permission.isGranted;
    if (!granted && await permission.isPermanentlyDenied) {
      _snack('اجازه بسته شده؛ از تنظیمات برنامه روشنش کنید.');
      await openAppSettings();
    }
  }

  Permission get _audioPermission => _status.sdk >= 33 ? Permission.audio : Permission.storage;

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    final dir = await Directory.systemTemp.createTemp('stt-test-');
    try {
      final file = File('${dir.path}/silence.wav')..writeAsBytesSync(_silentWav());
      final stt = OpenAiCompatibleTranscriber(
        baseUrl: _baseUrl.text,
        apiKey: _apiKey.text,
        model: _model.text.trim().isEmpty ? 'whisper-1' : _model.text.trim(),
        language: _language.text.trim(),
        timeout: const Duration(seconds: 40),
      );
      final result = await stt.transcribe(file);
      _testOk = true;
      _testMessage = 'اتصال برقرار است ✓ (پاسخ آزمایشی: «${result.text.isEmpty ? 'بدون متن، چون فایل آزمایشی بی‌صداست' : result.text}»)';
    } on TranscriptionException catch (e) {
      _testOk = false;
      _testMessage = e.message;
    } on FormatException catch (e) {
      _testOk = false;
      _testMessage = e.message;
    } catch (e) {
      _testOk = false;
      _testMessage = 'خطا: $e';
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    if (mounted) setState(() => _testing = false);
  }

  /// یک ثانیه سکوتِ WAV (۱۶ کیلوهرتز، ۱۶ بیت، تک‌کاناله) برای آزمایش اتصال.
  Uint8List _silentWav() {
    const sampleRate = 16000;
    const dataLength = sampleRate * 2;
    final bytes = BytesBuilder();
    void u32(int v) => bytes.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
    void u16(int v) => bytes.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
    bytes
      ..add('RIFF'.codeUnits)
      ..add(Uint8List(0));
    u32(36 + dataLength);
    bytes.add('WAVEfmt '.codeUnits);
    u32(16);
    u16(1);
    u16(1);
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    bytes.add('data'.codeUnits);
    u32(dataLength);
    bytes.add(Uint8List(dataLength));
    return bytes.takeBytes();
  }

  Future<void> _save() async {
    if (!_settings.consentAccepted) {
      _snack('ابتدا اطلاعیه‌ی مسئولیت ضبط را بپذیرید.');
      return;
    }
    if (_settings.uploadEnabled) {
      final uri = Uri.tryParse(_uploadUrl.text.trim());
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        _snack('آدرس «ارسال به سرور» معتبر نیست (مثال: https://example.com/api/calls).');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final updated = _settings.copyWith(
        setupCompleted: true,
        sttBaseUrl: _baseUrl.text.trim().isEmpty ? 'https://api.openai.com/v1' : _baseUrl.text.trim(),
        sttModel: _model.text.trim().isEmpty ? 'whisper-1' : _model.text.trim(),
        language: _language.text.trim(),
        uploadUrl: _uploadUrl.text.trim(),
      );
      await CallSettingsStorage.update(
        (current) => updated.copyWith(lastScanAtMillis: current.lastScanAtMillis),
      );
      await CallSecrets.saveSttKey(_apiKey.text);
      await CallSecrets.saveUploadToken(_uploadToken.text);
      await SmsBridge.configureCallRecorder(
        enabled: updated.inAppRecorderEnabled,
        autoSpeaker: updated.autoSpeaker,
      );
      final service = FlutterBackgroundService();
      if (await service.isRunning()) service.invoke('scanRecordings');
      if (!mounted) return;
      setState(() => _settings = updated);
      _snack('ذخیره شد. از این به بعد ضبط‌ها خودکار پیدا و به متن تبدیل می‌شوند.');
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('ضبط تماس')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final guide = guideFor(_brand);

    return Scaffold(
      appBar: AppBar(title: const Text('ضبط تماس و تبدیل به متن')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _chain(theme),
          const SizedBox(height: 14),
          _consentCard(theme),
          if (_settings.consentAccepted) ...[
            const SizedBox(height: 14),
            _permissionsCard(theme),
            const SizedBox(height: 14),
            _builtInCard(theme, guide),
            const SizedBox(height: 14),
            _inAppCard(theme),
            const SizedBox(height: 14),
            _transcriptionCard(theme),
            const SizedBox(height: 14),
            _uploadCard(theme),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: const Text('ذخیره و شروع کار خودکار'),
        ),
      ),
    );
  }

  // ── بخش‌ها ────────────────────────────────────────────────────────────────

  Widget _chain(ThemeData theme) {
    return _Card(
      icon: Icons.account_tree_rounded,
      color: AppColors.primary,
      title: 'چطور کار می‌کند',
      child: Text(
        '۱) تماس انجام می‌شود و ضبط‌کننده‌ی گوشی (یا ضبط داخلی) آن را ذخیره می‌کند.\n'
        '۲) برنامه فایل را خودکار پیدا می‌کند و به همان تماس در تاریخچه‌ی گوشی وصل می‌کند.\n'
        '۳) صدا به سرویس تبدیل به متنی که شما وارد می‌کنید فرستاده می‌شود.\n'
        '۴) متن کنار صدا ذخیره می‌شود و در تب «تماس‌ها» قابل جست‌وجو است.\n\n'
        'بعد از یک‌بار تنظیم، نیازی به دست زدن نیست.',
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.9),
      ),
    );
  }

  Widget _consentCard(ThemeData theme) {
    final accepted = _settings.consentAccepted;
    return _Card(
      icon: Icons.gavel_rounded,
      color: accepted ? AppColors.success : AppColors.warning,
      title: 'اطلاعیه‌ی مسئولیت ضبط تماس',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kRecordingConsentText, style: theme.textTheme.bodyMedium?.copyWith(height: 1.8)),
          const SizedBox(height: 10),
          if (accepted)
            const StatusPill(label: 'پذیرفته شد', color: AppColors.success, icon: Icons.check_circle_rounded)
          else
            FilledButton.icon(
              onPressed: _acceptConsent,
              icon: const Icon(Icons.check_rounded),
              label: const Text('می‌خوانم و مسئولیت را می‌پذیرم'),
            ),
        ],
      ),
    );
  }

  Widget _permissionsCard(ThemeData theme) {
    Widget row(String label, String why, bool ok, Permission? permission) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: ok ? AppColors.success : AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(why, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (!ok && permission != null)
              TextButton(onPressed: () => _request(permission), child: const Text('اجازه بده')),
          ],
        ),
      );
    }

    return _Card(
      icon: Icons.verified_user_rounded,
      color: AppColors.secondary,
      title: 'مجوزهای لازم',
      child: Column(
        children: [
          row('تاریخچه‌ی تماس', 'برای وصل کردن ضبط به شماره، نام و زمان تماس', _status.callLog, Permission.phone),
          row('فایل‌های صوتی', 'برای پیدا کردن فایل ضبط‌کننده‌ی گوشی', _status.audioMedia, _audioPermission),
          row('میکروفون', 'فقط برای ضبط داخلی (آزمایشی)', _status.recordAudio, Permission.microphone),
          row('اعلان‌ها', 'برای پایداری سرویس پس‌زمینه', _status.notifications, Permission.notification),
        ],
      ),
    );
  }

  Widget _builtInCard(ThemeData theme, BrandGuide guide) {
    return _Card(
      icon: Icons.phone_in_talk_rounded,
      color: AppColors.accent,
      title: 'روش ۱ (پیشنهادی): ضبط‌کننده‌ی خودِ گوشی',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'گوشی شما: ${_status.manufacturer.isEmpty ? 'نامشخص' : '${_status.manufacturer} ${_status.model}'} '
            '(اندروید ${_status.sdk > 0 ? _androidName(_status.sdk) : '؟'})',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('برند تشخیص‌داده‌شده: ${guide.title}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Text('برای روشن کردن ضبط خودکار در خودِ گوشی:', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          for (var i = 0; i < guide.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.18),
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: AppColors.accent)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(guide.steps[i], style: theme.textTheme.bodyMedium?.copyWith(height: 1.7))),
                ],
              ),
            ),
          const SizedBox(height: 6),
          _note(theme, Icons.folder_open_rounded, 'محل ذخیره: ${guide.folderHint}'),
          if (guide.caveat.isNotEmpty) _note(theme, Icons.warning_amber_rounded, guide.caveat, color: AppColors.warning),
          if (!guide.canWatchFolder)
            _note(
              theme,
              Icons.block_rounded,
              'روی این برند فایل ضبط برای برنامه‌ی دیگر قابل خواندن نیست؛ «روش ۲» را روشن کنید.',
              color: AppColors.error,
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.watchPhoneRecorder,
            onChanged: (v) => setState(() => _settings = _settings.copyWith(watchPhoneRecorder: v)),
            title: const Text('پیدا کردن خودکار فایل‌های ضبط‌کننده‌ی گوشی'),
            subtitle: const Text('پوشه‌های سامسونگ، شیائومی، هواوی، اوپو/ریلمی/وان‌پلاس، ویوو و ضبط‌کننده‌های دیگر بررسی می‌شود.'),
          ),
        ],
      ),
    );
  }

  Widget _inAppCard(ThemeData theme) {
    final ok = _status.accessibility;
    return _Card(
      icon: Icons.mic_rounded,
      color: AppColors.warning,
      title: 'روش ۲: ضبط داخلی (آزمایشی، بهترین تلاش)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(
            theme,
            Icons.science_outlined,
            'اندروید ۱۰ به بعد برنامه‌ها را از ضبط مستقیم صدای تماس منع کرده؛ این روش فقط با «میکروفون» ضبط می‌کند. '
            'صدای شما واضح ضبط می‌شود ولی صدای طرف مقابل فقط وقتی که از بلندگوی گوشی پخش شود. '
            'در بعضی گوشی‌ها اندروید در زمان تماس میکروفون را از برنامه‌ها می‌گیرد و فایل بی‌صدا می‌شود (برنامه چنین فایلی را دور می‌ریزد و خطا را اینجا نشان می‌دهد). '
            'وقتی گوشی ضبط‌کننده‌ی خودش را دارد، روش ۱ را ترجیح دهید.',
            color: AppColors.warning,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.inAppRecorderEnabled,
            onChanged: (v) => setState(() => _settings = _settings.copyWith(inAppRecorderEnabled: v)),
            title: const Text('ضبط داخلی هنگام تماس'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.autoSpeaker,
            onChanged: _settings.inAppRecorderEnabled
                ? (v) => setState(() => _settings = _settings.copyWith(autoSpeaker: v))
                : null,
            title: const Text('روشن کردن خودکار بلندگو'),
            subtitle: const Text('تا صدای طرف مقابل هم ضبط شود. (طرف مقابل ممکن است متوجه شود؛ در بعضی گوشی‌ها اندروید اجازه نمی‌دهد.)'),
          ),
          if (_settings.inAppRecorderEnabled) ...[
            const Divider(),
            Row(
              children: [
                Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                    color: ok ? AppColors.success : AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ok ? 'سرویس دسترس‌پذیری «ضبط تماس» روشن است' : 'سرویس دسترس‌پذیری هنوز روشن نیست',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (!ok) ...[
              const SizedBox(height: 8),
              Text(
                'اندروید به برنامه‌ها اجازه نمی‌دهد در پس‌زمینه ضبط کنند، مگر «سرویس دسترس‌پذیری» روشن باشد. مراحل:\n'
                '۱) دکمه‌ی زیر را بزنید.\n'
                '۲) «برنامه‌های نصب‌شده / Installed apps» ← «ضبط تماس (پیامک و تماس)» را باز کنید.\n'
                '۳) کلید را روشن کنید و تأیید بزنید.\n'
                'اگر اندروید ۱۳ به بعد کلید خاکستری بود: تنظیمات ← برنامه‌ها ← «پیامک و تماس» ← منوی ⋮ بالا ← «Allow restricted settings» (اجازه‌ی تنظیمات محدودشده)، بعد دوباره به مرحله‌ی ۱ برگردید.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.8),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: SmsBridge.openAccessibilitySettings,
                    icon: const Icon(Icons.accessibility_new_rounded, size: 18),
                    label: const Text('باز کردن تنظیمات دسترس‌پذیری'),
                  ),
                  OutlinedButton.icon(
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_applications_rounded, size: 18),
                    label: const Text('اطلاعات برنامه'),
                  ),
                ],
              ),
            ],
            if (_recorder.lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              _note(theme, Icons.error_outline_rounded, _recorder.lastError, color: AppColors.error),
            ],
            if (_recorder.lastRecordingAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('آخرین ضبط داخلی: ${formatCallWhen(_recorder.lastRecordingAt!)}', style: theme.textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }

  Widget _transcriptionCard(ThemeData theme) {
    final enabled = _settings.provider == TranscriptionProvider.openAiCompatible;
    return _Card(
      icon: Icons.record_voice_over_rounded,
      color: AppColors.primary,
      title: 'تبدیل صدا به متن',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'هر سرویس سازگار با OpenAI (آدرس …/audio/transcriptions) کار می‌کند: خودِ OpenAI، Groq، یا سرور Whisper شخصی. '
            'مدل صوتی از خود برنامه دانلود نمی‌شود. کلید فقط روی همین گوشی، رمزشده نگه داشته می‌شود.',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.8, color: theme.colorScheme.onSurfaceVariant),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: (v) => setState(
              () => _settings = _settings.copyWith(
                provider: v ? TranscriptionProvider.openAiCompatible : TranscriptionProvider.none,
              ),
            ),
            title: const Text('تبدیل خودکار به متن'),
          ),
          if (enabled) ...[
            TextField(
              controller: _baseUrl,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'آدرس سرویس',
                hintText: 'https://api.openai.com/v1',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKey,
              textDirection: TextDirection.ltr,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'کلید API (اگر سرور شخصی بدون کلید است خالی بگذارید)',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _model,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'مدل', hintText: 'whisper-1'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _language,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'زبان', hintText: 'fa'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check_rounded, size: 18),
                label: const Text('آزمایش اتصال'),
              ),
            ),
            if (_testMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _note(
                  theme,
                  _testOk ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  _testMessage!,
                  color: _testOk ? AppColors.success : AppColors.error,
                ),
              ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.autoTranscribe,
            onChanged: (v) => setState(() => _settings = _settings.copyWith(autoTranscribe: v)),
            title: const Text('ضبط‌های تازه خودکار در صف تبدیل بروند'),
          ),
        ],
      ),
    );
  }

  Widget _uploadCard(ThemeData theme) {
    return _Card(
      icon: Icons.cloud_upload_rounded,
      color: AppColors.secondary,
      title: 'ارسال به سرور خودم (اختیاری)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ضبط و اطلاعات تماس (شماره، نام، زمان، جهت، مدت) به آدرسی که می‌دهید POST می‌شود. '
            'اگر سرور در پاسخ {"text": "..."} برگرداند، به‌عنوان متن مکالمه ذخیره می‌شود.',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.8, color: theme.colorScheme.onSurfaceVariant),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.uploadEnabled,
            onChanged: (v) => setState(() => _settings = _settings.copyWith(uploadEnabled: v)),
            title: const Text('ارسال به سرور'),
          ),
          if (_settings.uploadEnabled) ...[
            TextField(
              controller: _uploadUrl,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'آدرس دریافت',
                hintText: 'https://example.com/api/calls',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _uploadToken,
              textDirection: TextDirection.ltr,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'توکن (Bearer)، اختیاری', prefixIcon: Icon(Icons.key_rounded)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _settings.uploadIncludeAudio,
              onChanged: (v) => setState(() => _settings = _settings.copyWith(uploadIncludeAudio: v)),
              title: const Text('فایل صوتی هم فرستاده شود'),
              subtitle: const Text('اگر خاموش باشد فقط اطلاعات تماس و متن می‌رود.'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _note(ThemeData theme, IconData icon, String text, {Color? color}) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(height: 1.7))),
        ],
      ),
    );
  }

  String _androidName(int sdk) {
    const names = {
      24: '7', 25: '7.1', 26: '8', 27: '8.1', 28: '9', 29: '10', 30: '11',
      31: '12', 32: '12L', 33: '13', 34: '14', 35: '15', 36: '16',
    };
    return names[sdk] ?? 'API $sdk';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.color, required this.title, required this.child});

  final IconData icon;
  final Color color;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
