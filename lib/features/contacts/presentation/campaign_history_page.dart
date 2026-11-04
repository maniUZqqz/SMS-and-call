import 'package:flutter/material.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/core/utils/persian_date.dart';
import 'package:untitled3/features/contacts/data/campaign_storage.dart';
import 'package:untitled3/features/contacts/domain/sms_campaign.dart';

class CampaignHistoryPage extends StatefulWidget {
  const CampaignHistoryPage({super.key});

  @override
  State<CampaignHistoryPage> createState() => _CampaignHistoryPageState();
}

class _CampaignHistoryPageState extends State<CampaignHistoryPage> {
  List<CampaignHistory> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final history = await CampaignStorage.loadHistory();
    if (!mounted) return;
    setState(() {
      _items = history
          .where(
            (campaign) =>
                campaign.requestedCount > 1 ||
                campaign.scheduledCampaignId != null,
          )
          .toList(growable: false);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تاریخچه پیام‌های انبوه'),
        actions: [
          IconButton(
            tooltip: 'تازه‌سازی',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? const _EmptyCampaignHistory()
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _CampaignHistoryCard(
                          campaign: item,
                          onTap: item.recipients.isEmpty
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        CampaignDetailsPage(campaign: item),
                                  ),
                                ),
                        );
                      },
                    ),
            ),
    );
  }
}

class CampaignDetailsPage extends StatelessWidget {
  const CampaignDetailsPage({super.key, required this.campaign});

  final CampaignHistory campaign;

  @override
  Widget build(BuildContext context) {
    final unattempted = campaign.unattemptedRecipients;
    final unattemptedTitle = switch (campaign.state) {
      CampaignState.windowEnded => 'ارسال‌نشده به‌دلیل پایان زمان',
      CampaignState.cancelled => 'ارسال‌نشده به‌دلیل توقف کمپین',
      CampaignState.failed => 'ارسال‌نشده به‌دلیل توقف با خطا',
      _ => 'ارسال‌نشده',
    };

    return Scaffold(
      appBar: AppBar(title: Text(campaign.title ?? 'جزئیات گیرندگان')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            sliver: SliverToBoxAdapter(
              child: _CampaignSummary(campaign: campaign),
            ),
          ),
          ..._recipientSection(
            context,
            title: 'ارسال‌شده',
            color: AppColors.success,
            icon: Icons.done_all_rounded,
            recipients: campaign.sentRecipients,
          ),
          ..._recipientSection(
            context,
            title: 'ناموفق',
            color: AppColors.error,
            icon: Icons.error_outline_rounded,
            recipients: campaign.failedRecipients,
          ),
          ..._recipientSection(
            context,
            title: unattemptedTitle,
            color: AppColors.warning,
            icon: Icons.timer_off_outlined,
            recipients: unattempted,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  List<Widget> _recipientSection(
    BuildContext context, {
    required String title,
    required Color color,
    required IconData icon,
    required List<CampaignRecipient> recipients,
  }) {
    if (recipients.isEmpty) return const <Widget>[];
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                '$title (${recipients.length})',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: recipients.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _RecipientTile(
              recipient: recipients[index],
              color: color,
              icon: icon,
            ),
          ),
        ),
      ),
    ];
  }
}

class _CampaignHistoryCard extends StatelessWidget {
  const _CampaignHistoryCard({required this.campaign, required this.onTap});

  final CampaignHistory campaign;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = campaign.recipients.isEmpty
        ? (campaign.requestedCount - campaign.sentCount - campaign.failedCount)
              .clamp(0, campaign.requestedCount)
        : campaign.unattemptedRecipients.length;
    final status = _campaignStatus(campaign.state);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
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
                          status.label,
                          style: TextStyle(
                            color: status.color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _dateTimeLabel(context, campaign.finishedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
              const SizedBox(height: 13),
              if (campaign.title != null &&
                  campaign.title!.trim().isNotEmpty) ...[
                Text(
                  campaign.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                campaign.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _CountChip(
                    label: '${campaign.sentCount} ارسال‌شده',
                    color: AppColors.success,
                  ),
                  if (campaign.failedCount > 0)
                    _CountChip(
                      label: '${campaign.failedCount} ناموفق',
                      color: AppColors.error,
                    ),
                  if (remaining > 0)
                    _CountChip(
                      label: campaign.state == CampaignState.windowEnded
                          ? '$remaining بدون زمان'
                          : '$remaining ارسال‌نشده',
                      color: AppColors.warning,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 17,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_campaignWindow(campaign)} · ${campaign.requestedCount} مخاطب',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (campaign.recipients.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'جزئیات نام‌ها برای این رکورد قدیمی موجود نیست.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CampaignSummary extends StatelessWidget {
  const _CampaignSummary({required this.campaign});

  final CampaignHistory campaign;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.secondary.withValues(alpha: 0.14),
            AppColors.surfaceRaised,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (campaign.title != null && campaign.title!.trim().isNotEmpty) ...[
            Text(
              campaign.title!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            campaign.message,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 10),
          Text(
            '${_dateTimeLabel(context, campaign.finishedAt)} · ${_campaignWindow(campaign)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.recipient,
    required this.color,
    required this.icon,
  });

  final CampaignRecipient recipient;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              recipient.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            recipient.phone,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyCampaignHistory extends StatelessWidget {
  const _EmptyCampaignHistory();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 100),
        const Icon(
          Icons.history_toggle_off_rounded,
          size: 54,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 14),
        Text(
          'هنوز پیام انبوهی ثبت نشده است',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          'بعد از پایان هر کمپین، نتیجه و وضعیت گیرندگان اینجا نمایش داده می‌شود.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

({String label, IconData icon, Color color}) _campaignStatus(
  CampaignState state,
) {
  return switch (state) {
    CampaignState.completed => (
      label: 'کمپین تکمیل شد',
      icon: Icons.done_all_rounded,
      color: AppColors.success,
    ),
    CampaignState.windowEnded => (
      label: 'بازه زمانی تمام شد',
      icon: Icons.timer_off_outlined,
      color: AppColors.warning,
    ),
    CampaignState.cancelled => (
      label: 'کمپین متوقف شد',
      icon: Icons.stop_circle_outlined,
      color: AppColors.warning,
    ),
    _ => (
      label: 'کمپین با خطا متوقف شد',
      icon: Icons.error_outline_rounded,
      color: AppColors.error,
    ),
  };
}

String _time(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _dateTimeLabel(BuildContext context, DateTime value) {
  final date = MaterialLocalizations.of(context).formatMediumDate(value);
  return '$date · ${_time(value)}';
}

String _campaignWindow(CampaignHistory campaign) {
  final dailyStart = campaign.dailyStartMinute;
  final dailyEnd = campaign.dailyEndMinute;
  if (dailyStart != null && dailyEnd != null) {
    return '${formatPersianDateRange(campaign.startsAt, campaign.endsAt)} · '
        'هر روز ${_minuteTime(dailyStart)} تا ${_minuteTime(dailyEnd)}';
  }
  return 'بازه ${_time(campaign.startsAt)} تا ${_time(campaign.endsAt)}';
}

String _minuteTime(int minute) {
  return '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';
}
