import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sms_and_call/core/theme/app_theme.dart';
import 'package:sms_and_call/core/utils/persian_date.dart';
import 'package:sms_and_call/features/calls/data/call_settings.dart';
import 'package:sms_and_call/features/calls/data/recording_repository.dart';
import 'package:sms_and_call/features/calls/domain/call_models.dart';
import 'package:sms_and_call/features/calls/presentation/call_format.dart';
import 'package:sms_and_call/features/calls/presentation/call_setup_page.dart';
import 'package:sms_and_call/features/calls/presentation/recording_detail_page.dart';
import 'package:sms_and_call/features/calls/services/call_cycle.dart';

/// تب «تماس‌ها»: فهرست ضبط‌ها با جست‌وجو در نام، شماره و متن مکالمه.
class RecordingsTab extends StatefulWidget {
  const RecordingsTab({super.key, this.repository});

  final RecordingRepository? repository;

  @override
  State<RecordingsTab> createState() => _RecordingsTabState();
}

class _RecordingsTabState extends State<RecordingsTab> with WidgetsBindingObserver {
  late final RecordingRepository _repo = widget.repository ?? RecordingRepository();
  final _searchController = TextEditingController();
  StreamSubscription<Map<String, dynamic>?>? _changed;
  Timer? _debounce;

  List<CallRecording> _items = const [];
  CallSettings _settings = const CallSettings();
  RecordingFilter _filter = RecordingFilter.all;
  String _query = '';
  bool _loading = true;
  bool _syncing = false;
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changed = FlutterBackgroundService().on('recordingsChanged').listen((_) => unawaited(_reload()));
    unawaited(_init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changed?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_sync(quiet: true));
  }

  Future<void> _init() async {
    await _reload();
    // اولین اجرا: راهنمای مرحله‌به‌مرحله‌ی فعال‌کردن ضبط برای برند همین گوشی
    if (!_settings.setupCompleted && !_autoOpened) {
      _autoOpened = true;
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (mounted) await _openSetup();
    } else {
      unawaited(_sync(quiet: true));
    }
  }

  Future<void> _reload() async {
    final settings = await CallSettingsStorage.load();
    final items = await _repo.search(_query, filter: _filter);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _items = items;
      _loading = false;
    });
  }

  /// ضبط‌های تازه را پیدا و پردازش می‌کند (همان چرخه‌ی سرویس پس‌زمینه).
  Future<void> _sync({bool quiet = false}) async {
    if (_syncing || !_settings.consentAccepted) return;
    setState(() => _syncing = true);
    try {
      final report = await CallCycle(repository: _repo).run();
      if (!quiet && mounted && !report.skipped) {
        final imported = report.scan?.imported ?? 0;
        _snack(
          imported > 0
              ? '${toPersianDigits(imported)} ضبط تازه پیدا شد.'
              : 'ضبط تازه‌ای پیدا نشد.',
        );
      }
      FlutterBackgroundService().invoke('scanRecordings');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    await _reload();
  }

  Future<void> _openSetup() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CallSetupPage()),
    );
    await _reload();
    unawaited(_sync(quiet: true));
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _onQuery(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => unawaited(_reload()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: () => _sync(),
      child: CustomScrollView(
        key: const PageStorageKey('recordings-tab'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(child: _StatusCard(settings: _settings, syncing: _syncing, onSetup: _openSetup, onSync: () => _sync())),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: TextField(
                controller: _searchController,
                onChanged: _onQuery,
                decoration: const InputDecoration(
                  hintText: 'جست‌وجو در نام، شماره و متن مکالمه',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            sliver: SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in const {
                      RecordingFilter.all: 'همه',
                      RecordingFilter.withText: 'دارای متن',
                      RecordingFilter.pending: 'در صف',
                      RecordingFilter.failed: 'ناموفق',
                      RecordingFilter.unlinked: 'بدون اتصال به تماس',
                    }.entries)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(entry.value),
                          selected: _filter == entry.key,
                          onSelected: (_) {
                            _filter = entry.key;
                            unawaited(_reload());
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.mic_none_rounded, size: 54, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      _query.isNotEmpty || _filter != RecordingFilter.all
                          ? 'موردی پیدا نشد.'
                          : 'هنوز ضبطی نیست.\nبعد از اولین تماسِ ضبط‌شده اینجا می‌آید.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
              sliver: SliverList.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return _RecordingCard(
                    recording: item,
                    onTap: () async {
                      final removed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (_) => RecordingDetailPage(recordingId: item.id, repository: _repo),
                        ),
                      );
                      await _reload();
                      if (removed == true) _snack('ضبط حذف شد.');
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.settings, required this.syncing, required this.onSetup, required this.onSync});

  final CallSettings settings;
  final bool syncing;
  final VoidCallback onSetup;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = settings.consentAccepted && settings.setupCompleted;
    final color = ready ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ready ? Icons.mic_rounded : Icons.info_outline_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready ? 'ضبط، اتصال به تماس و تبدیل به متن خودکار است' : 'ضبط تماس هنوز راه‌اندازی نشده',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: settings.watchPhoneRecorder ? 'رصد ضبط‌کننده‌ی گوشی: روشن' : 'رصد ضبط‌کننده‌ی گوشی: خاموش',
                color: settings.watchPhoneRecorder ? AppColors.success : AppColors.textSecondary,
              ),
              StatusPill(
                label: settings.inAppRecorderEnabled ? 'ضبط داخلی (آزمایشی): روشن' : 'ضبط داخلی: خاموش',
                color: settings.inAppRecorderEnabled ? AppColors.success : AppColors.textSecondary,
              ),
              StatusPill(
                label: settings.canTranscribe ? 'تبدیل به متن: تنظیم شده' : 'تبدیل به متن: تنظیم نشده',
                color: settings.canTranscribe ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSetup,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(ready ? 'تنظیمات ضبط تماس' : 'راه‌اندازی ضبط تماس'),
                ),
              ),
              if (settings.consentAccepted) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: syncing ? null : onSync,
                  icon: syncing
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('بررسی'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.recording, required this.onTap});

  final CallRecording recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = recording;
    final statusColor = transcriptStatusColor(r.transcriptStatus);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.secondary.withValues(alpha: 0.14),
                foregroundColor: AppColors.secondary,
                child: Icon(callDirectionIcon(r.direction)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        formatCallWhen(r.when),
                        if (r.callDuration != null) formatCallDuration(r.callDuration!),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusPill(label: transcriptStatusLabel(r.transcriptStatus), color: statusColor),
                        if (!r.linked)
                          const StatusPill(label: 'بدون اتصال به تماس', color: AppColors.warning, icon: Icons.link_off_rounded),
                        if (!r.hasAudio)
                          const StatusPill(label: 'صدا حذف شده', color: AppColors.textSecondary),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
