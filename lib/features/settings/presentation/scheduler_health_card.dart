import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/core/theme/app_theme.dart';
import 'package:sms_and_call/core/utils/persian_date.dart';

/// وضعیت «بیداری زمان‌بندی»: آیا آلارم دقیق مجاز است، آخرین بیداری چه شد، و دکمه‌ی آزمایش.
/// کمپین‌های زمان‌بندی‌شده با آلارم سیستم‌عامل بیدار می‌شوند؛ این کارت نشان می‌دهد درست کار می‌کند.
class SchedulerHealthCard extends StatefulWidget {
  const SchedulerHealthCard({super.key, required this.status});

  final BridgeStatus status;

  @override
  State<SchedulerHealthCard> createState() => _SchedulerHealthCardState();
}

class _SchedulerHealthCardState extends State<SchedulerHealthCard>
    with WidgetsBindingObserver {
  WakeStatus _wake = WakeStatus.unknown;
  DateTime? _testAt;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final wake = await SmsBridge.wakeStatus();
    if (!mounted) return;
    setState(() => _wake = wake);
  }

  Future<void> _selfTest() async {
    final at = DateTime.now().add(const Duration(seconds: 60));
    final mode = await SmsBridge.scheduleWake(at, reason: 'selftest', slot: 'selftest');
    if (!mounted) return;
    setState(() => _testAt = at);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            mode == 'failed'
                ? 'ثبت آلارم آزمایشی ناموفق بود.'
                : 'آلارم آزمایشی برای ۶۰ ثانیه‌ی دیگر ثبت شد؛ می‌توانید برنامه را ببندید و صفحه را خاموش کنید.',
          ),
        ),
      );
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _refresh();
      if (DateTime.now().isAfter(at.add(const Duration(minutes: 3)))) timer.cancel();
    });
  }

  bool get _testPassed {
    final at = _testAt;
    final fired = _wake.lastFiredAt;
    return at != null &&
        fired != null &&
        _wake.lastFiredReason == 'selftest' &&
        fired.isAfter(at.subtract(const Duration(seconds: 70)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exactOk = widget.status.exactAlarm;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                exactOk ? Icons.alarm_on_rounded : Icons.alarm_off_rounded,
                color: exactOk ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  exactOk
                      ? 'آلارم دقیق مجاز است: کمپین‌ها سر ساعتِ تعیین‌شده بیدار می‌شوند'
                      : 'آلارم دقیق بسته است؛ کمپین‌ها ممکن است تا چند دقیقه دیرتر شروع شوند',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (!exactOk) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: SmsBridge.openExactAlarmSettings,
                icon: const Icon(Icons.alarm_add_rounded, size: 18),
                label: const Text('اجازه‌ی «آلارم‌ها و یادآورها»'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _wake.nextWakeAt != null
                ? 'بیداری بعدی: ${formatPersianDateTime(_wake.nextWakeAt!)}'
                : 'بیداری ثبت‌شده‌ای نیست (کمپین فعالی وجود ندارد).',
            style: theme.textTheme.bodySmall,
          ),
          if (_wake.lastFiredAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'آخرین بیداری: ${formatPersianDateTime(_wake.lastFiredAt!)} '
                '(${_wake.lastStartedService ? 'سرویس بالا آمد' : 'سرویس بالا نیامد'})'
                '${_wake.lastError.isEmpty ? '' : ' — ${_wake.lastError}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _wake.lastStartedService ? null : AppColors.warning,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _selfTest,
                icon: const Icon(Icons.timer_rounded, size: 18),
                label: const Text('آزمایش زمان‌بندی (۶۰ ثانیه)'),
              ),
              OutlinedButton.icon(
                onPressed: SmsBridge.openAutoStartSettings,
                icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                label: const Text('شروع خودکار / باتری گوشی'),
              ),
            ],
          ),
          if (_testAt != null) ...[
            const SizedBox(height: 10),
            Text(
              _testPassed
                  ? 'آزمایش موفق بود ✓ آلارم در ساعتِ مقرر گوشی را بیدار کرد.'
                  : 'منتظر نتیجه‌ی آزمایش… اگر بعد از دو دقیقه این پیام عوض نشد، گوشی آلارم را به تأخیر انداخته '
                      '(بهینه‌سازی باتری یا «شروع خودکار» را بررسی کنید).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _testPassed ? AppColors.success : AppColors.warning,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
