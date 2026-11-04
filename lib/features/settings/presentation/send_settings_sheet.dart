import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sms_and_call/features/contacts/domain/contact.dart';
import 'package:sms_and_call/features/settings/domain/send_settings.dart';
import 'package:sms_and_call/features/settings/presentation/widgets/sheet_header.dart';

/// تنظیمات «احتیاط در ارسال»: فاصله‌ی بین پیامک‌ها، سقف ساعتی و تلاش دوباره.
class SendSettingsSheet extends StatefulWidget {
  const SendSettingsSheet({super.key, required this.initial});

  final SendSettings initial;

  @override
  State<SendSettingsSheet> createState() => _SendSettingsSheetState();
}

class _SendSettingsSheetState extends State<SendSettingsSheet> {
  late final TextEditingController _delay;
  late final TextEditingController _perHour;
  late final TextEditingController _perDay;
  late final TextEditingController _retries;
  late double _jitter;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _delay = TextEditingController(text: '${s.minDelaySeconds}');
    _perHour = TextEditingController(text: '${s.maxPerHour}');
    _perDay = TextEditingController(text: '${s.maxPerDay}');
    _retries = TextEditingController(text: '${s.retryAttempts}');
    _jitter = s.jitterPercent.toDouble();
  }

  @override
  void dispose() {
    _delay.dispose();
    _perHour.dispose();
    _perDay.dispose();
    _retries.dispose();
    super.dispose();
  }

  int _read(TextEditingController c, int fallback) =>
      int.tryParse(normalizePhoneNumber(c.text)) ?? fallback;

  void _save() {
    final base = widget.initial;
    Navigator.of(context).pop(
      base
          .copyWith(
            minDelaySeconds: _read(_delay, base.minDelaySeconds),
            maxPerHour: _read(_perHour, base.maxPerHour),
            maxPerDay: _read(_perDay, base.maxPerDay),
            retryAttempts: _read(_retries, base.retryAttempts),
            jitterPercent: _jitter.round(),
          )
          .normalized(),
    );
  }

  Widget _number(TextEditingController c, String label, String help, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩]'))],
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          helperMaxLines: 3,
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(
              icon: Icons.speed_rounded,
              title: 'احتیاط در ارسال',
              subtitle: 'برای اینکه اپراتور سیم‌کارت را مسدود نکند',
            ),
            const SizedBox(height: 16),
            _number(
              _delay,
              'کمترین فاصله بین دو پیامک (ثانیه)',
              'حتی اگر در کمپین فاصله‌ی کمتری بگذارید، از این کمتر نمی‌شود (حداقل ۳).',
              Icons.timer_outlined,
            ),
            Text(
              'تصادفی‌سازی فاصله: ${_jitter.round()}٪',
              style: theme.textTheme.bodyMedium,
            ),
            Slider(
              value: _jitter,
              max: 100,
              divisions: 20,
              label: '${_jitter.round()}٪',
              onChanged: (value) => setState(() => _jitter = value),
            ),
            Text(
              'به هر فاصله کمی زمان اضافه می‌شود تا ارسال مثل ربات یکنواخت نباشد.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _number(
              _perHour,
              'سقف پیامک در هر ساعت (۰ = بدون سقف)',
              'رسیدن به سقف، ارسال را تا آزاد شدن جا متوقف می‌کند و بعد خودکار ادامه می‌دهد.',
              Icons.hourglass_bottom_rounded,
            ),
            _number(
              _perDay,
              'سقف پیامک در هر شبانه‌روز (۰ = بدون سقف)',
              'بسیاری از اپراتورها سقف روزانه دارند؛ عدد مجاز سیم‌کارت‌تان را بگذارید.',
              Icons.today_rounded,
            ),
            _number(
              _retries,
              'تعداد تلاش دوباره برای خطای موقت',
              'مثلاً نبودن آنتن: با فاصله‌ی ۳۰ ثانیه، ۲ و ۵ دقیقه دوباره امتحان می‌شود.',
              Icons.replay_rounded,
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }
}
