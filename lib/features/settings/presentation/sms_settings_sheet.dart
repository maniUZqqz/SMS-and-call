import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/core/constants/app_constants.dart';
import 'package:untitled3/core/errors/error_classifier.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/logs/presentation/log_style.dart';
import 'package:untitled3/features/settings/domain/server_config.dart';
import 'package:untitled3/features/settings/presentation/widgets/sheet_header.dart';

class SmsSettingsSheet extends StatefulWidget {
  final ServerConfig initialConfig;

  const SmsSettingsSheet({super.key, required this.initialConfig});

  @override
  State<SmsSettingsSheet> createState() => _SmsSettingsSheetState();
}

class _SmsSettingsSheetState extends State<SmsSettingsSheet> {
  late final TextEditingController _tplCtrl;
  final TextEditingController _testCtrl = TextEditingController();

  SimQuery _q = SimQuery.empty;
  bool _loading = true;

  late int _subId;
  late int _slot;
  late String _label;

  bool _testing = false;
  String? _testMsg;
  bool _testOk = false;
  String? _tplError;

  static const List<String> _presets = [
    'کد تایید شما:',
    'کد ورود شما:',
    'Your code:',
  ];

  @override
  void initState() {
    super.initState();

    _tplCtrl = TextEditingController(text: widget.initialConfig.smsTemplate);
    _subId = widget.initialConfig.simSubscriptionId;
    _slot = widget.initialConfig.simSlot;
    _label = widget.initialConfig.simLabel;

    _loadSims();
  }

  @override
  void dispose() {
    _tplCtrl.dispose();
    _testCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSims() async {
    setState(() => _loading = true);
    final q = await SmsBridge.getSimCards();
    if (!mounted) return;
    setState(() {
      _q = q;
      _loading = false;
    });
  }

  Future<void> _grantPhone() async {
    try {
      final st = await Permission.phone.request();
      if (st.isPermanentlyDenied || st.isRestricted) {
        await openAppSettings();
      }
    } catch (_) {}
    await _loadSims();
  }

  void _pick(SimCard? s) {
    setState(() {
      if (s == null) {
        _subId = -1;
        _slot = -1;
        _label = '';
      } else {
        _subId = s.subscriptionId;
        _slot = s.slot;
        _label = s.title;
      }
    });
  }

  ServerConfig _draft() => widget.initialConfig.copyWith(
    smsTemplate: _tplCtrl.text,
    simSubscriptionId: _subId,
    simSlot: _slot,
    simLabel: _label,
  );

  String _lengthInfo(String msg) {
    final unicode = msg.runes.any((r) => r > 127);
    final single = unicode ? 70 : 160;
    final multi = unicode ? 67 : 153;
    final len = msg.runes.length;
    final parts = len <= single ? 1 : (len / multi).ceil();
    return '$len کاراکتر · $parts پیامک';
  }

  void _save() {
    final t = _tplCtrl.text;

    if (t.length > 300) {
      setState(() => _tplError = 'متن خیلی طولانی است (حداکثر ۳۰۰ کاراکتر)');
      return;
    }

    Navigator.of(context).pop(_draft());
  }

  Future<void> _test() async {
    final phone = _testCtrl.text.trim();

    if (RegExp(r'\d').allMatches(phone).length < 5) {
      setState(() {
        _testOk = false;
        _testMsg = 'شماره‌ی گیرنده را کامل وارد کنید.';
      });
      return;
    }

    setState(() {
      _testing = true;
      _testMsg = null;
    });

    final cfg = _draft();
    final q = await SmsBridge.getSimCards();
    final subId = pickSubId(cfg, q);

    final r = await SmsBridge.sendSms(
      to: phone,
      message: cfg.buildMessage('123456'),
      subId: subId,
    );

    if (!mounted) return;

    if (r.ok) {
      setState(() {
        _testing = false;
        _testOk = true;
        _testMsg = 'پیامک از ${simNameOf(q.sims, r.usedSubId)} ارسال شد.';
      });
    } else {
      final info = ErrorClassifier.smsResult(r);
      setState(() {
        _testing = false;
        _testOk = false;
        _testMsg =
            '${info.title}\n${info.hint}\n(${info.technical.split('\n').first})';
      });
    }
  }

  Widget _optionTile({
    required ThemeData theme,
    required IconData icon,
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.55)
            : cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? cs.primary : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: selected ? cs.primary : cs.outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.outline,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _simSection(ThemeData theme) {
    final cs = theme.colorScheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_q.permissionGranted) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'برای دیدن و انتخاب سیم‌کارت‌ها مجوز «تلفن» لازم است. تا آن موقع از سیم‌کارت پیش‌فرض گوشی استفاده می‌شود.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
            ),
            const SizedBox(height: 6),
            FilledButton.tonal(
              onPressed: _grantPhone,
              child: const Text('اجازه‌ی دسترسی'),
            ),
          ],
        ),
      );
    }

    final defaultSim = _q.sims
        .where((s) => s.subscriptionId == _q.defaultSmsSubId)
        .toList();

    final defaultSubtitle = defaultSim.isNotEmpty
        ? 'اکنون: ${defaultSim.first.title}'
        : (_q.sims.length > 1
              ? 'در گوشی تعیین نشده (هر بار می‌پرسد)؛ برنامه خودش اولین سیم را برمی‌دارد'
              : null);

    final savedMissing =
        _subId >= 0 &&
        !_q.sims.any((s) => s.subscriptionId == _subId) &&
        !_q.sims.any((s) => _slot >= 0 && s.slot == _slot);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _optionTile(
          theme: theme,
          icon: Icons.phone_android_rounded,
          title: 'پیش‌فرض گوشی',
          subtitle: defaultSubtitle,
          selected: _subId < 0,
          onTap: () => _pick(null),
        ),
        for (final s in _q.sims)
          _optionTile(
            theme: theme,
            icon: Icons.sim_card_rounded,
            title: s.title,
            subtitle: [
              if (s.number.isNotEmpty) s.number,
              if (s.embedded) 'eSIM',
            ].join(' · '),
            selected:
                _subId == s.subscriptionId ||
                (_subId >= 0 &&
                    !_q.sims.any((x) => x.subscriptionId == _subId) &&
                    _slot == s.slot),
            onTap: () => _pick(s),
          ),
        if (_q.sims.isEmpty)
          Text(
            'سیم‌کارت فعالی پیدا نشد.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
          ),
        if (savedMissing)
          Text(
            'سیم‌کارت ذخیره‌شده (${_label.isEmpty ? 'نامشخص' : _label}) در گوشی نیست؛ یکی را انتخاب کنید.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final msg = widget.initialConfig
        .copyWith(smsTemplate: _tplCtrl.text)
        .buildMessage('123456');

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(
              icon: Icons.sms_rounded,
              title: 'تنظیمات پیامک',
              subtitle: 'سیم‌کارت ارسال و متن قبل از کد',
            ),
            const SizedBox(height: 18),
            Text(
              'ارسال از',
              style: theme.textTheme.labelLarge?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 8),
            _simSection(theme),
            const SizedBox(height: 14),
            Text(
              'متن قبل از کد',
              style: theme.textTheme.labelLarge?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tplCtrl,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => setState(() => _tplError = null),
              decoration: InputDecoration(
                hintText: 'مثلاً: کد تایید شما:',
                errorText: _tplError,
                prefixIcon: const Icon(Icons.edit_note_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                for (final p in _presets)
                  ActionChip(
                    label: Text(p),
                    onPressed: () => setState(() {
                      _tplCtrl.text = p;
                      _tplError = null;
                    }),
                  ),
                ActionChip(
                  label: const Text('فقط کد'),
                  onPressed: () => setState(() {
                    _tplCtrl.text = '';
                    _tplError = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg,
                    textDirection: dirFor(msg),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'پیش‌نمایش با کد نمونه · ${_lengthInfo(msg)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'نکته: اگر در متن {code} بنویسید، کد دقیقاً همان‌جا قرار می‌گیرد.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                leading: const Icon(Icons.science_outlined),
                title: const Text('ارسال آزمایشی'),
                children: [
                  TextField(
                    controller: _testCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    decoration: InputDecoration(
                      labelText: 'شماره‌ی گیرنده',
                      hintText: '09123456789',
                      prefixIcon: const Icon(Icons.phone_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('ارسال با تنظیمات بالا'),
                    ),
                  ),
                  if (_testMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _testMsg!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.55,
                          color: _testOk ? AppColors.success : cs.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'یک پیامک واقعی فرستاده می‌شود و ممکن است هزینه داشته باشد.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _tplCtrl.text = kDefaultTemplate;
                      _pick(null);
                      _tplError = null;
                    }),
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
                    label: const Text('ذخیره'),
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
    );
  }
}
