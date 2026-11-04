import 'package:flutter/material.dart';
import 'package:untitled3/features/settings/domain/server_config.dart';
import 'package:untitled3/features/settings/presentation/widgets/sheet_header.dart';

class ServerSettingsSheet extends StatefulWidget {
  final ServerConfig initialConfig;

  const ServerSettingsSheet({super.key, required this.initialConfig});

  @override
  State<ServerSettingsSheet> createState() => _ServerSettingsSheetState();
}

class _ServerSettingsSheetState extends State<ServerSettingsSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _baseUrlCtrl;

  late final TextEditingController _otpPathCtrl;

  late final TextEditingController _markSentPathCtrl;

  bool _advancedOpen = false;

  @override
  void initState() {
    super.initState();

    _baseUrlCtrl = TextEditingController(text: widget.initialConfig.baseUrl);

    _otpPathCtrl = TextEditingController(text: widget.initialConfig.otpPath);

    _markSentPathCtrl = TextEditingController(
      text: widget.initialConfig.markSentPath,
    );
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _otpPathCtrl.dispose();
    _markSentPathCtrl.dispose();

    super.dispose();
  }

  String? _validateBaseUrl(String? value) {
    final v = (value ?? '').trim();

    if (v.isEmpty) {
      return 'آدرس سرور را وارد کنید';
    }

    final uri = Uri.tryParse(v);

    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'آدرس معتبر نیست (مثال: http://192.168.1.10:5000)';
    }

    return null;
  }

  String? _validatePath(String? value) {
    final v = (value ?? '').trim();

    if (v.isEmpty) {
      return 'مسیر را وارد کنید';
    }

    if (!v.startsWith('/')) {
      return 'مسیر باید با / شروع شود';
    }

    return null;
  }

  void _restoreDefaults() {
    final d = ServerConfig.defaults();

    setState(() {
      _baseUrlCtrl.text = d.baseUrl;
      _otpPathCtrl.text = d.otpPath;
      _markSentPathCtrl.text = d.markSentPath;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // فیلدهای پیامک/سیم‌کارت دست‌نخورده می‌مانند
    final config = widget.initialConfig.copyWith(
      baseUrl: _baseUrlCtrl.text.trim(),
      otpPath: _otpPathCtrl.text.trim(),
      markSentPath: _markSentPathCtrl.text.trim(),
    );

    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fieldFill = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.35,
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(
                icon: Icons.dns_rounded,
                title: 'تنظیمات سرور',
                subtitle: 'آدرس دریافت کد و مسیرهای API را تغییر دهید',
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _baseUrlCtrl,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'آدرس پایه سرور (Base URL)',
                  hintText: 'http://192.168.43.47:5000',
                  prefixIcon: const Icon(Icons.link_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  filled: true,
                  fillColor: fieldFill,
                ),
                validator: _validateBaseUrl,
              ),
              const SizedBox(height: 8),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _advancedOpen,
                  onExpansionChanged: (v) => setState(() => _advancedOpen = v),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('مسیرهای پیشرفته API'),
                  children: [
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _otpPathCtrl,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      decoration: InputDecoration(
                        labelText: 'مسیر دریافت کد',
                        hintText: '/api/next-otp',
                        prefixIcon: const Icon(Icons.download_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        filled: true,
                        fillColor: fieldFill,
                      ),
                      validator: _validatePath,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _markSentPathCtrl,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      decoration: InputDecoration(
                        labelText: 'مسیر ثبت ارسال',
                        hintText: '/api/mark-sent',
                        prefixIcon: const Icon(Icons.upload_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        filled: true,
                        fillColor: fieldFill,
                      ),
                      validator: _validatePath,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _restoreDefaults,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('پیش‌فرض'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('ذخیره تنظیمات'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
