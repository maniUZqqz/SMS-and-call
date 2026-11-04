import 'package:flutter/material.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/home/presentation/widgets/stat_tile.dart';
import 'package:untitled3/features/logs/domain/log_entry.dart';
import 'package:untitled3/features/logs/presentation/log_style.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({
    super.key,
    required this.running,
    required this.connectionLabel,
    required this.connectionDetail,
    required this.connectionColor,
    required this.connectionIcon,
    required this.sent,
    required this.failed,
    required this.polls,
    required this.nativeBridgeAvailable,
    required this.smsPermissionGranted,
    required this.missingPermissions,
    required this.serverUrl,
    required this.simTitle,
    required this.messagePreview,
    required this.latestLog,
    required this.onRefresh,
    required this.onStart,
    required this.onStop,
    required this.onOpenPermissions,
    required this.onOpenServer,
    required this.onOpenSms,
    required this.onOpenActivity,
  });

  final bool running;
  final String connectionLabel;
  final String? connectionDetail;
  final Color connectionColor;
  final IconData connectionIcon;
  final int sent;
  final int failed;
  final int polls;
  final bool nativeBridgeAvailable;
  final bool smsPermissionGranted;
  final int missingPermissions;
  final String serverUrl;
  final String simTitle;
  final String messagePreview;
  final LogEntry? latestLog;
  final Future<void> Function() onRefresh;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onOpenPermissions;
  final VoidCallback onOpenServer;
  final VoidCallback onOpenSms;
  final VoidCallback onOpenActivity;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('dashboard-tab'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ConnectionCard(
            running: running,
            label: connectionLabel,
            detail: connectionDetail,
            color: connectionColor,
            icon: connectionIcon,
            onStart: onStart,
            onStop: onStop,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.mark_email_read_rounded,
                  value: '$sent',
                  label: 'ارسال‌شده',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  icon: Icons.error_outline_rounded,
                  value: '$failed',
                  label: 'خطا',
                  color: failed > 0 ? AppColors.error : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  icon: Icons.sync_rounded,
                  value: '$polls',
                  label: 'بررسی',
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            title: 'آمادگی سیستم',
            subtitle: 'موارد ضروری برای کارکرد پایدار',
          ),
          const SizedBox(height: 10),
          _HealthCard(
            nativeBridgeAvailable: nativeBridgeAvailable,
            smsPermissionGranted: smsPermissionGranted,
            missingPermissions: missingPermissions,
            onTap: onOpenPermissions,
          ),
          const SizedBox(height: 20),
          _SectionTitle(
            title: 'آخرین فعالیت',
            subtitle: latestLog == null
                ? 'هنوز رویدادی ثبت نشده'
                : 'خلاصه آخرین رویداد سرویس',
            actionLabel: 'مشاهده همه',
            onAction: onOpenActivity,
          ),
          const SizedBox(height: 10),
          _LatestActivityCard(entry: latestLog, onTap: onOpenActivity),
          const SizedBox(height: 20),
          const _SectionTitle(
            title: 'دسترسی سریع',
            subtitle: 'پیکربندی‌های پرکاربرد',
          ),
          const SizedBox(height: 10),
          _QuickSettingCard(
            icon: Icons.dns_rounded,
            color: AppColors.secondary,
            title: 'سرور',
            value: serverUrl,
            valueDirection: TextDirection.ltr,
            onTap: onOpenServer,
          ),
          const SizedBox(height: 8),
          _QuickSettingCard(
            icon: Icons.sim_card_rounded,
            color: AppColors.accent,
            title: simTitle,
            value: messagePreview,
            valueDirection: dirFor(messagePreview),
            onTap: onOpenSms,
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.running,
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
    required this.onStart,
    required this.onStop,
  });

  final bool running;
  final String label;
  final String? detail;
  final Color color;
  final IconData icon;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            color.withValues(alpha: 0.18),
            colorScheme.surfaceContainerHigh,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 27),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      running ? 'گیت‌وی فعال' : 'گیت‌وی غیرفعال',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        detail!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: running
                ? OutlinedButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('توقف سرویس'),
                  )
                : FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('راه‌اندازی سرویس'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.nativeBridgeAvailable,
    required this.smsPermissionGranted,
    required this.missingPermissions,
    required this.onTap,
  });

  final bool nativeBridgeAvailable;
  final bool smsPermissionGranted;
  final int missingPermissions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String title;
    final String subtitle;

    if (!nativeBridgeAvailable) {
      color = AppColors.error;
      icon = Icons.extension_off_rounded;
      title = 'پل بومی در دسترس نیست';
      subtitle = 'ساخت یا نصب برنامه باید بررسی شود';
    } else if (!smsPermissionGranted) {
      color = AppColors.error;
      icon = Icons.sms_failed_rounded;
      title = 'مجوز پیامک غیرفعال است';
      subtitle = 'بدون این مجوز ارسالی انجام نمی‌شود';
    } else if (missingPermissions > 0) {
      color = AppColors.warning;
      icon = Icons.shield_outlined;
      title = '$missingPermissions مورد نیاز به بررسی دارد';
      subtitle = 'برای پایداری سرویس، دسترسی‌ها را کامل کنید';
    } else {
      color = AppColors.success;
      icon = Icons.verified_user_rounded;
      title = 'سیستم آماده ارسال است';
      subtitle = 'همه دسترسی‌ها و تنظیمات ضروری فعال‌اند';
    }

    return _ActionSurface(
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

class _LatestActivityCard extends StatelessWidget {
  const _LatestActivityCard({required this.entry, required this.onTap});

  final LogEntry? entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = entry;
    if (value == null) {
      return const _ActionSurface(
        icon: Icons.inbox_rounded,
        color: AppColors.textSecondary,
        title: 'منتظر اولین رویداد',
        subtitle: 'پس از شروع سرویس، فعالیت‌ها اینجا دیده می‌شوند',
      );
    }

    final color = levelColor(value.level, Theme.of(context).colorScheme);
    return _ActionSurface(
      icon: kindIcon(value.kind),
      color: color,
      title: value.title,
      subtitle: value.kind == LogKind.flow
          ? '${fmtTime(value.time)} · ${value.flowSummary}'
          : '${fmtTime(value.time)} · ${kindLabel(value.kind)}',
      onTap: onTap,
    );
  }
}

class _QuickSettingCard extends StatelessWidget {
  const _QuickSettingCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.valueDirection,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final TextDirection valueDirection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _IconBox(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: valueDirection,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_left_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionSurface extends StatelessWidget {
  const _ActionSurface({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _IconBox(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_left_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}
