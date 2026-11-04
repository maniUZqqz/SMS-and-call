import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/core/utils/persian_date.dart';
import 'package:untitled3/features/campaigns/data/scheduled_campaign_storage.dart';
import 'package:untitled3/features/campaigns/domain/scheduled_campaign.dart';
import 'package:untitled3/features/campaigns/presentation/campaign_editor_page.dart';
import 'package:untitled3/features/contacts/data/campaign_storage.dart';
import 'package:untitled3/features/contacts/domain/sms_campaign.dart';
import 'package:untitled3/features/contacts/presentation/campaign_history_page.dart';

enum _CampaignAction { edit, delete }

class CampaignsTab extends StatefulWidget {
  const CampaignsTab({super.key, required this.onEnsureReady});

  final Future<bool> Function() onEnsureReady;

  @override
  State<CampaignsTab> createState() => _CampaignsTabState();
}

class _CampaignsTabState extends State<CampaignsTab>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>?>? _changedSubscription;
  StreamSubscription<Map<String, dynamic>?>? _statusSubscription;
  List<ScheduledCampaign> _campaigns = const [];
  SmsCampaign? _activeRuntime;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final service = FlutterBackgroundService();
    _changedSubscription = service
        .on('scheduledCampaignsChanged')
        .listen((_) => unawaited(_load()));
    _statusSubscription = service.on('campaignStatus').listen((event) {
      if (event == null) return;
      final raw = event['campaign'];
      if (raw is Map) {
        final runtime = SmsCampaign.fromJson(Map<String, dynamic>.from(raw));
        if (runtime.scheduledCampaignId != null) _activeRuntime = runtime;
      } else if (event['state'] == 'idle') {
        _activeRuntime = null;
      }
      unawaited(_load());
    });
    unawaited(_load());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      service.invoke('requestCampaignStatus');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changedSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final campaigns = await ScheduledCampaignStorage.load();
    final active = await CampaignStorage.loadActive();
    if (!mounted) return;
    setState(() {
      _campaigns = campaigns;
      _activeRuntime = active?.scheduledCampaignId == null ? null : active;
      _loading = false;
    });
  }

  Future<void> _openEditor([ScheduledCampaign? campaign]) async {
    if (_saving) return;
    if (campaign != null && !campaign.canEditAt(DateTime.now())) {
      _snack('با رسیدن روز شروع، کمپین دیگر قابل ویرایش نیست.');
      return;
    }
    final active = await CampaignStorage.loadActive();
    if (!mounted) return;
    final result = await Navigator.of(context).push<ScheduledCampaign>(
      MaterialPageRoute<ScheduledCampaign>(
        builder: (_) => CampaignEditorPage(
          campaigns: _campaigns,
          initialCampaign: campaign,
          activeRuntime: active,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ScheduledCampaignStorage.upsert(result);
      await _load();
      final ready = await widget.onEnsureReady();
      FlutterBackgroundService().invoke('reloadScheduledCampaigns');
      if (!mounted) return;
      _snack(
        ready
            ? campaign == null
                  ? 'کمپین ذخیره و زمان‌بندی شد.'
                  : 'تغییرات کمپین ذخیره شد.'
            : 'کمپین ذخیره شد؛ برای اجرای خودکار، مجوز پیامک و سرویس را فعال کنید.',
      );
    } catch (_) {
      if (mounted) _snack('ذخیره کمپین انجام نشد. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCampaign(ScheduledCampaign campaign) async {
    final running =
        campaign.state == ScheduledCampaignState.sending ||
        _activeRuntime?.scheduledCampaignId == campaign.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          running ? Icons.stop_circle_outlined : Icons.delete_outline_rounded,
          color: AppColors.error,
        ),
        title: Text(running ? 'توقف و حذف کمپین' : 'حذف کمپین'),
        content: Text(
          running
              ? 'ارسال «${campaign.title}» متوقف و کمپین حذف شود؟ پیام‌های ارسال‌شده در تاریخچه باقی می‌مانند.'
              : 'کمپین «${campaign.title}» برای همیشه حذف شود؟ تاریخچه ارسال‌های انجام‌شده پاک نمی‌شود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text(running ? 'توقف و حذف' : 'حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    FlutterBackgroundService().invoke('deleteScheduledCampaign', {
      'id': campaign.id,
    });
    await ScheduledCampaignStorage.delete(campaign.id);
    await _load();
    if (mounted) _snack('کمپین حذف شد.');
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CampaignHistoryPage()),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final current = _campaigns
        .where((campaign) => !campaign.isTerminal)
        .toList(growable: false);
    final finished = _campaigns
        .where((campaign) => campaign.isTerminal)
        .toList(growable: false);
    final sending = current
        .where((campaign) => campaign.state == ScheduledCampaignState.sending)
        .length;
    final waiting = current.length - sending;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              sliver: SliverToBoxAdapter(
                child: _CampaignOverview(
                  waiting: waiting,
                  sending: sending,
                  finished: finished.length,
                  onHistory: _openHistory,
                ),
              ),
            ),
            if (_campaigns.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyCampaigns(onCreate: _openEditor),
              )
            else ...[
              if (current.isNotEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(18, 4, 18, 9),
                  sliver: SliverToBoxAdapter(
                    child: _ListHeading(
                      title: 'فعال و آینده',
                      icon: Icons.upcoming_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              _campaignList(current),
              if (finished.isNotEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(18, 22, 18, 9),
                  sliver: SliverToBoxAdapter(
                    child: _ListHeading(
                      title: 'پایان‌یافته',
                      icon: Icons.history_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              _campaignList(finished),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ],
        ),
      ),
      floatingActionButton: _campaigns.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _openEditor,
              icon: const Icon(Icons.add_rounded),
              label: const Text('کمپین جدید'),
            ),
    );
  }

  Widget _campaignList(List<ScheduledCampaign> campaigns) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: campaigns.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final campaign = campaigns[index];
          return _CampaignCard(
            campaign: campaign,
            activeRuntime: _activeRuntime,
            onEdit: campaign.canEditAt(DateTime.now())
                ? () => _openEditor(campaign)
                : null,
            onDelete: () => _deleteCampaign(campaign),
          );
        },
      ),
    );
  }
}

class _CampaignOverview extends StatelessWidget {
  const _CampaignOverview({
    required this.waiting,
    required this.sending,
    required this.finished,
    required this.onHistory,
  });

  final int waiting;
  final int sending;
  final int finished;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF16273B), Color(0xFF111827)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.secondary, AppColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.schedule_send_rounded,
                  color: Color(0xFF08111F),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ارسال دقیق، بدون مراقبت دستی',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'تاریخ شمسی و ساعت روزانه را یک‌بار تنظیم کنید.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تاریخچه ارسال انبوه',
                onPressed: onHistory,
                icon: const Icon(Icons.history_rounded),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _OverviewStat(
                  value: '$sending',
                  label: 'در حال ارسال',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OverviewStat(
                  value: '$waiting',
                  label: 'در انتظار',
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OverviewStat(
                  value: '$finished',
                  label: 'پایان‌یافته',
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.screen_lock_portrait_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'با فعال‌بودن سرویس، ارسال هنگام خاموش‌بودن صفحه هم ادامه پیدا می‌کند.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.activeRuntime,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduledCampaign campaign;
  final SmsCampaign? activeRuntime;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusView(campaign, DateTime.now());
    final runtime = activeRuntime?.scheduledCampaignId == campaign.id
        ? activeRuntime
        : campaign.execution;
    final total = runtime?.totalCount ?? campaign.selectedRecipients.length;
    final processed = runtime == null
        ? 0
        : runtime.sentCount + runtime.failedCount;
    final progress = total == 0 ? 0.0 : (processed / total).clamp(0.0, 1.0);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(status.icon, color: status.color, size: 22),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          campaign.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          status.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: status.color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_CampaignAction>(
                    tooltip: 'گزینه‌های کمپین',
                    onSelected: (action) {
                      if (action == _CampaignAction.edit) {
                        onEdit?.call();
                      } else {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      if (onEdit != null)
                        const PopupMenuItem(
                          value: _CampaignAction.edit,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_calendar_outlined),
                            title: Text('ویرایش'),
                          ),
                        ),
                      const PopupMenuItem(
                        value: _CampaignAction.delete,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.error,
                          ),
                          title: Text('حذف'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                campaign.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 12),
              _InfoLine(
                icon: Icons.date_range_rounded,
                text: formatPersianDateRange(
                  campaign.startDate,
                  campaign.endDate,
                ),
              ),
              _InfoLine(
                icon: Icons.schedule_rounded,
                text:
                    'هر روز ${_minuteTime(campaign.dailyStartMinute)} تا ${_minuteTime(campaign.dailyEndMinute)} · هر ${_interval(campaign.intervalSeconds)}',
              ),
              _InfoLine(
                icon: campaign.audience == CampaignAudience.allAtStart
                    ? Icons.all_inclusive_rounded
                    : Icons.groups_2_outlined,
                text: campaign.audience == CampaignAudience.allAtStart
                    ? runtime == null
                          ? 'همه مخاطبان در لحظه شروع'
                          : 'همه مخاطبان در شروع · ${runtime.totalCount} نفر'
                    : '${campaign.selectedRecipients.length} مخاطب انتخابی',
              ),
              if (runtime != null && total > 0) ...[
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: AppColors.surfaceHighest,
                    color: status.color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${runtime.sentCount} ارسال‌شده · ${runtime.failedCount} ناموفق · ${runtime.remainingCount} باقی‌مانده',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (campaign.lastError != null &&
                  campaign.lastError!.trim().isNotEmpty) ...[
                const SizedBox(height: 9),
                Text(
                  campaign.lastError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
              if (onEdit == null && !campaign.isTerminal) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_clock_outlined,
                      color: AppColors.textSecondary,
                      size: 17,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'روز شروع رسیده؛ برای حفظ زمان‌بندی فقط حذف امکان‌پذیر است.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListHeading extends StatelessWidget {
  const _ListHeading({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 7),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _EmptyCampaigns extends StatelessWidget {
  const _EmptyCampaigns({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_note_rounded,
                size: 39,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'اولین کمپین را بسازید',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'پیام، تاریخ شمسی، ساعت روزانه و مخاطبان را مشخص کنید؛ ادامه کار خودکار انجام می‌شود.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('ساخت کمپین'),
            ),
          ],
        ),
      ),
    );
  }
}

({String label, IconData icon, Color color}) _statusView(
  ScheduledCampaign campaign,
  DateTime now,
) {
  return switch (campaign.state) {
    ScheduledCampaignState.sending => (
      label: 'در حال ارسال',
      icon: Icons.send_rounded,
      color: AppColors.success,
    ),
    ScheduledCampaignState.completed => (
      label: 'ارسال کامل شد',
      icon: Icons.done_all_rounded,
      color: AppColors.success,
    ),
    ScheduledCampaignState.windowEnded => (
      label: 'بازه تمام شد',
      icon: Icons.timer_off_outlined,
      color: AppColors.warning,
    ),
    ScheduledCampaignState.failed => (
      label: 'متوقف با خطا',
      icon: Icons.error_outline_rounded,
      color: AppColors.error,
    ),
    ScheduledCampaignState.cancelled => (
      label: 'متوقف‌شده',
      icon: Icons.stop_circle_outlined,
      color: AppColors.warning,
    ),
    ScheduledCampaignState.waiting =>
      campaign.execution != null
          ? (
              label: 'در انتظار ادامه ارسال',
              icon: Icons.more_time_rounded,
              color: AppColors.warning,
            )
          : dateOnly(now).isBefore(campaign.startDate)
          ? (
              label: 'در انتظار تاریخ شروع',
              icon: Icons.calendar_month_rounded,
              color: AppColors.secondary,
            )
          : (
              label: 'در انتظار ساعت ارسال',
              icon: Icons.schedule_rounded,
              color: AppColors.warning,
            ),
  };
}

String _minuteTime(int minute) {
  final hour = (minute ~/ 60).toString().padLeft(2, '0');
  final minutes = (minute % 60).toString().padLeft(2, '0');
  return '$hour:$minutes';
}

String _interval(int seconds) {
  if (seconds >= 60 && seconds % 60 == 0) return '${seconds ~/ 60} دقیقه';
  return '$seconds ثانیه';
}
