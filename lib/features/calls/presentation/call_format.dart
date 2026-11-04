import 'package:flutter/material.dart';
import 'package:sms_and_call/core/theme/app_theme.dart';
import 'package:sms_and_call/core/utils/persian_date.dart';
import 'package:sms_and_call/features/calls/domain/call_models.dart';

/// `۱۴ آبان ۱۴۰۵ · ۱۴:۲۵`
String formatCallWhen(DateTime value) => formatPersianDateTime(value);

/// مدت به صورت `۳:۰۵` یا `۱:۰۲:۱۰`
String formatCallDuration(Duration value) {
  final total = value.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  final text = h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  return toPersianDigits(text);
}

IconData callDirectionIcon(CallDirection direction) {
  switch (direction) {
    case CallDirection.incoming:
      return Icons.call_received_rounded;
    case CallDirection.outgoing:
      return Icons.call_made_rounded;
    case CallDirection.missed:
      return Icons.call_missed_rounded;
    case CallDirection.rejected:
    case CallDirection.blocked:
      return Icons.call_end_rounded;
    case CallDirection.unknown:
      return Icons.phone_in_talk_rounded;
  }
}

Color transcriptStatusColor(TranscriptStatus status) {
  switch (status) {
    case TranscriptStatus.done:
      return AppColors.success;
    case TranscriptStatus.failed:
      return AppColors.error;
    case TranscriptStatus.queued:
    case TranscriptStatus.running:
      return AppColors.warning;
    case TranscriptStatus.none:
      return AppColors.textSecondary;
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
