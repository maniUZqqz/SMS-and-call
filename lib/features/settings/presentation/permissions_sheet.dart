import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/settings/presentation/widgets/sheet_header.dart';

class _PermItem {
  const _PermItem({
    required this.icon,
    required this.title,
    required this.desc,
    required this.ok,
    required this.required,
    required this.permission,
    this.alwaysSettings = false,
  });

  final IconData icon;
  final String title;
  final String desc;
  final bool ok;
  final bool required;
  final Permission permission;
  final bool alwaysSettings;
}

class PermissionsSheet extends StatefulWidget {
  const PermissionsSheet({super.key});

  @override
  State<PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<PermissionsSheet>
    with WidgetsBindingObserver {
  BridgeStatus _s = BridgeStatus.unknown;
  bool _loading = true;
  Permission? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await SmsBridge.status();
    if (!mounted) return;
    setState(() {
      _s = s;
      _loading = false;
    });
  }

  List<_PermItem> _items() => [
    _PermItem(
      icon: Icons.sms_rounded,
      title: 'ارسال پیامک',
      desc: 'برای فرستادن کد تایید از سیم‌کارت گوشی',
      ok: _s.sendSms,
      required: true,
      permission: Permission.sms,
    ),
    _PermItem(
      icon: Icons.sim_card_rounded,
      title: 'دسترسی به سیم‌کارت‌ها',
      desc: 'برای نمایش و انتخاب سیم‌کارت (مجوز «تلفن»)',
      ok: _s.phoneState,
      required: false,
      permission: Permission.phone,
    ),
    _PermItem(
      icon: Icons.notifications_active_rounded,
      title: 'اعلان‌ها',
      desc: 'برای نمایش اعلان ثابت سرویس پس‌زمینه',
      ok: _s.notifications,
      required: false,
      permission: Permission.notification,
    ),
    _PermItem(
      icon: Icons.battery_charging_full_rounded,
      title: 'اجرا بدون محدودیت باتری',
      desc: 'تا اندروید سرویس را با بستن برنامه یا خاموشی صفحه نکشد',
      ok: _s.battery,
      required: false,
      permission: Permission.ignoreBatteryOptimizations,
      alwaysSettings: true,
    ),
  ];

  Future<void> _fix(_PermItem item) async {
    setState(() => _busy = item.permission);

    try {
      await item.permission.request();
    } catch (_) {}

    await _refresh();

    final okNow = _items()
        .firstWhere((e) => e.permission == item.permission)
        .ok;

    if (!okNow) {
      PermissionStatus? st;
      try {
        st = await item.permission.status;
      } catch (_) {}

      if (item.alwaysSettings ||
          st == null ||
          st.isPermanentlyDenied ||
          st.isRestricted) {
        await openAppSettings();
      }
    }

    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final items = _items();

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
              icon: Icons.verified_user_rounded,
              title: 'بررسی مجوزها',
              subtitle: 'برای کار پایدار، به‌خصوص وقتی برنامه بسته است',
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (!_s.available)
                _note(
                  theme,
                  Icons.error_rounded,
                  cs.error,
                  'افزونه بومی پیامک پیدا نشد. پروژه را flutter clean کنید و دوباره build بگیرید.',
                ),
              if (_s.available && !_s.telephony)
                _note(
                  theme,
                  Icons.error_rounded,
                  cs.error,
                  'این دستگاه قابلیت پیامک (تلفن) ندارد.',
                ),
              if (_s.airplane)
                _note(
                  theme,
                  Icons.airplanemode_active_rounded,
                  AppColors.warning,
                  'حالت پرواز روشن است؛ تا خاموش نشود پیامکی ارسال نمی‌شود.',
                ),
              for (final it in items) _tile(theme, it),
              if (!_s.sendSms) ...[
                const SizedBox(height: 4),
                _note(
                  theme,
                  Icons.info_outline_rounded,
                  cs.primary,
                  'اگر پنجره‌ی درخواست مجوز پیامک ظاهر نشد (اندروید ۱۳+ برای برنامه‌هایی که از فروشگاه نصب نشده‌اند): '
                  'تنظیمات برنامه ← منوی ⋮ بالا ← «Allow restricted settings» را بزنید، بعد دوباره مجوز پیامک را بدهید.',
                ),
              ],
              const SizedBox(height: 4),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.help_outline_rounded),
                  title: const Text('با بستن برنامه سرویس می‌ایستد؟'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'در بعضی گوشی‌ها (شیائومی، سامسونگ، هواوی، اوپو، وان‌پلاس…) علاوه بر مجوزهای بالا باید '
                        '«شروع خودکار / Autostart» را برای این برنامه روشن کنید، باتری را روی «بدون محدودیت» بگذارید '
                        'و برنامه را در لیست اخیر «قفل» کنید.'
                        '${_s.manufacturer.isNotEmpty ? '\nدستگاه شما: ${_s.manufacturer} ${_s.model} (API ${_s.sdk})' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: openAppSettings,
                        icon: const Icon(Icons.settings_applications_rounded),
                        label: const Text('باز کردن تنظیمات برنامه'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _note(ThemeData theme, IconData icon, Color color, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(ThemeData theme, _PermItem it) {
    final cs = theme.colorScheme;
    const green = AppColors.success;
    const orange = AppColors.warning;

    final Color c = it.ok ? green : (it.required ? cs.error : orange);
    final busy = _busy == it.permission;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(it.icon, size: 19, color: c),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        it.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (it.required) ...[
                      const SizedBox(width: 6),
                      Text(
                        'ضروری',
                        style: TextStyle(fontSize: 10.5, color: cs.error),
                      ),
                    ],
                  ],
                ),
                Text(
                  it.desc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.outline,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (it.ok)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.check_circle_rounded, color: green),
            )
          else
            FilledButton.tonal(
              onPressed: busy ? null : () => _fix(it),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('فعال‌سازی'),
            ),
        ],
      ),
    );
  }
}
