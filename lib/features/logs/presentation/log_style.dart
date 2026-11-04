import 'package:flutter/material.dart' hide StepState;
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/logs/domain/log_entry.dart';

TextDirection dirFor(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s)
    ? TextDirection.rtl
    : TextDirection.ltr;

IconData kindIcon(LogKind k) {
  switch (k) {
    case LogKind.system:
      return Icons.settings_rounded;
    case LogKind.request:
      return Icons.north_east_rounded;
    case LogKind.response:
      return Icons.south_west_rounded;
    case LogKind.flow:
      return Icons.sms_rounded;
  }
}

Color levelColor(LogLevel l, ColorScheme cs) {
  switch (l) {
    case LogLevel.success:
      return AppColors.success;
    case LogLevel.warning:
      return AppColors.warning;
    case LogLevel.error:
      return cs.error;
    case LogLevel.info:
      return cs.primary;
  }
}

Color stepColor(StepState s, ColorScheme cs) {
  switch (s) {
    case StepState.ok:
      return AppColors.success;
    case StepState.warn:
      return AppColors.warning;
    case StepState.fail:
      return cs.error;
    case StepState.pending:
      return cs.outline;
  }
}

IconData stepIcon(StepState s) {
  switch (s) {
    case StepState.ok:
      return Icons.check_circle_rounded;
    case StepState.warn:
      return Icons.warning_amber_rounded;
    case StepState.fail:
      return Icons.cancel_rounded;
    case StepState.pending:
      return Icons.hourglass_top_rounded;
  }
}
