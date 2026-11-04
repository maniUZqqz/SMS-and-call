import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sms_and_call/core/theme/app_theme.dart';
import 'package:sms_and_call/core/utils/persian_date.dart';
import 'package:sms_and_call/features/contacts/domain/contact.dart';
import 'package:sms_and_call/features/optout/optout.dart';

/// فهرست «لغو»: شماره‌هایی که دیگر هیچ پیامک کمپینی نمی‌گیرند.
class OptOutPage extends StatefulWidget {
  const OptOutPage({super.key});

  @override
  State<OptOutPage> createState() => _OptOutPageState();
}

class _OptOutPageState extends State<OptOutPage> {
  final _controller = TextEditingController();
  List<OptOutEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await OptOutStorage.load();
    entries.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  /// چند شماره را یکجا می‌پذیرد (هر خط یا با فاصله/ویرگول جدا).
  Future<void> _addFromText() async {
    final numbers = _controller.text
        .split(RegExp(r'[\s,;،؛]+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    final valid = numbers.where(isValidPhoneNumber).toList();
    if (valid.isEmpty) {
      _snack('شماره‌ی معتبری پیدا نشد.');
      return;
    }
    final added = await OptOutStorage.addAll(
      valid.map((phone) => OptOutEntry.create(phone: phone)),
    );
    _controller.clear();
    await _load();
    final skipped = numbers.length - valid.length;
    _snack(
      '$added شماره به فهرست لغو اضافه شد'
      '${valid.length - added > 0 ? ' · ${valid.length - added} تکراری' : ''}'
      '${skipped > 0 ? ' · $skipped نامعتبر' : ''}.',
    );
  }

  Future<void> _remove(OptOutEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('برداشتن از فهرست لغو'),
        content: Text(
          'اگر ${entry.phone} را بردارید، دوباره در کمپین‌ها پیامک می‌گیرد. '
          'فقط اگر خودِ مشتری موافقت کرده این کار را بکنید.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('برداشتن'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await OptOutStorage.remove(entry.phone);
    await _load();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _sourceLabel(OptOutSource source) => switch (source) {
    OptOutSource.manual => 'دستی',
    OptOutSource.contact => 'از لیست مخاطبان',
    OptOutSource.import => 'از ستون «وضعیت» فایل',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('فهرست لغو')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Text(
              'به شماره‌های این فهرست هیچ پیامک کمپین یا ارسال گروهی فرستاده نمی‌شود، '
              'حتی اگر دوباره وارد مخاطبان شوند. در فایل Excel هم اگر ستونی با عنوان «وضعیت» '
              'مقدار «لغو» داشته باشد یا ستونی به نام «لغو» پر شده باشد، آن شماره‌ها خودکار اینجا می‌آیند.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.7),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 5,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'افزودن شماره (هر خط یک شماره)',
              hintText: '09123456789',
              prefixIcon: Icon(Icons.block_rounded),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _addFromText,
            icon: const Icon(Icons.add_rounded),
            label: const Text('افزودن به فهرست لغو'),
          ),
          const SizedBox(height: 18),
          Text(
            '${toPersianDigits(_entries.length)} شماره در فهرست',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'فهرست خالی است.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final entry in _entries)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.block_rounded, color: AppColors.error),
                  title: Text(
                    entry.name.isEmpty ? entry.phone : entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${entry.name.isEmpty ? '' : '${entry.phone} · '}'
                    '${_sourceLabel(entry.source)} · ${formatPersianDate(entry.addedAt)}',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: IconButton(
                    tooltip: 'برداشتن از فهرست',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _remove(entry),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
