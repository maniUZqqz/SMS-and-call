import 'package:flutter/material.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/logs/presentation/log_style.dart';
import 'package:untitled3/features/settings/domain/server_config.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.config,
    required this.bridgeStatus,
    required this.running,
    required this.missingPermissions,
    required this.onOpenServer,
    required this.onOpenSms,
    required this.onOpenPermissions,
    required this.onStart,
    required this.onStop,
  });

  final ServerConfig config;
  final BridgeStatus bridgeStatus;
  final bool running;
  final int missingPermissions;
  final VoidCallback onOpenServer;
  final VoidCallback onOpenSms;
  final VoidCallback onOpenPermissions;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const PageStorageKey('settings-tab'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SettingsIntro(
          ready:
              bridgeStatus.available &&
              bridgeStatus.sendSms &&
              missingPermissions == 0,
          missingPermissions: missingPermissions,
        ),
        const SizedBox(height: 20),
        const _SettingsSectionTitle(
          title: 'ارتباط و ارسال',
          subtitle: 'سرور مقصد و نحوه ارسال پیامک',
        ),
        const SizedBox(height: 10),
        _SettingsCard(
          icon: Icons.dns_rounded,
          color: AppColors.secondary,
          title: 'تنظیمات سرور',
          subtitle: 'آدرس و مسیرهای دریافت و ثبت کد',
          onTap: onOpenServer,
          children: [
            _ValueLine(
              label: 'آدرس',
              value: config.baseUrl,
              direction: TextDirection.ltr,
            ),
            _ValueLine(
              label: 'دریافت',
              value: config.otpPath,
              direction: TextDirection.ltr,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _SettingsCard(
          icon: Icons.sim_card_rounded,
          color: AppColors.accent,
          title: 'پیامک و سیم‌کارت',
          subtitle: 'انتخاب خط، قالب پیام و ارسال آزمایشی',
          onTap: onOpenSms,
          children: [
            _ValueLine(label: 'خط ارسال', value: config.simTitle),
            _ValueLine(
              label: 'نمونه',
              value: config.previewMessage,
              direction: dirFor(config.previewMessage),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SettingsSectionTitle(
          title: 'دسترسی و پایداری',
          subtitle: 'مجوزهای سیستم و اجرای پس‌زمینه',
        ),
        const SizedBox(height: 10),
        _SettingsCard(
          icon: Icons.admin_panel_settings_rounded,
          color: missingPermissions > 0 ? AppColors.warning : AppColors.success,
          title: 'مجوزها و باتری',
          subtitle: missingPermissions > 0
              ? '$missingPermissions مورد نیاز به بررسی دارد'
              : 'همه موارد ضروری فعال است',
          onTap: onOpenPermissions,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(label: 'پیامک', ok: bridgeStatus.sendSms),
                _StatusPill(label: 'سیم‌کارت', ok: bridgeStatus.phoneState),
                _StatusPill(label: 'اعلان', ok: bridgeStatus.notifications),
                _StatusPill(label: 'باتری', ok: bridgeStatus.battery),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ServiceControlCard(running: running, onStart: onStart, onStop: onStop),
        const SizedBox(height: 20),
        const _SettingsSectionTitle(
          title: 'دستگاه',
          subtitle: 'اطلاعات محیط اجرای گیت‌وی',
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              _DeviceLine(
                icon: Icons.phone_android_rounded,
                label: 'مدل',
                value: _deviceName,
              ),
              const SizedBox(height: 12),
              _DeviceLine(
                icon: Icons.android_rounded,
                label: 'نسخه Android',
                value: bridgeStatus.sdk > 0
                    ? 'API ${bridgeStatus.sdk}'
                    : 'نامشخص',
              ),
              const SizedBox(height: 12),
              _DeviceLine(
                icon: Icons.airplanemode_active_rounded,
                label: 'حالت پرواز',
                value: bridgeStatus.airplane ? 'روشن' : 'خاموش',
                valueColor: bridgeStatus.airplane
                    ? AppColors.warning
                    : AppColors.success,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get _deviceName {
    final value = '${bridgeStatus.manufacturer} ${bridgeStatus.model}'.trim();
    return value.isEmpty ? 'نامشخص' : value;
  }
}

class _SettingsIntro extends StatelessWidget {
  const _SettingsIntro({required this.ready, required this.missingPermissions});

  final bool ready;
  final int missingPermissions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ready ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.tune_rounded : Icons.info_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? 'پیکربندی آماده است' : 'پیکربندی را کامل کنید',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ready
                      ? 'سرور، پیامک و دسترسی‌های سیستم از این صفحه مدیریت می‌شوند.'
                      : '$missingPermissions مورد سیستمی هنوز نیاز به بررسی دارد.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.children,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
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
                  Icon(
                    Icons.chevron_left_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceControlCard extends StatelessWidget {
  const _ServiceControlCard({
    required this.running,
    required this.onStart,
    required this.onStop,
  });

  final bool running;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = running ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                running
                    ? Icons.play_circle_rounded
                    : Icons.pause_circle_rounded,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  running ? 'سرویس در حال اجراست' : 'سرویس متوقف است',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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

class _ValueLine extends StatelessWidget {
  const _ValueLine({required this.label, required this.value, this.direction});

  final String label;
  final String value;
  final TextDirection? direction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: direction,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.info_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

class _DeviceLine extends StatelessWidget {
  const _DeviceLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 19, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 9),
        Text(label, style: theme.textTheme.bodySmall),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: valueColor ?? theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
    );
  }
}
