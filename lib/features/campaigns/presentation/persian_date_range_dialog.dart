import 'package:flutter/material.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/core/utils/persian_date.dart';

Future<DateTimeRange?> showPersianDateRangeDialog({
  required BuildContext context,
  required DateTime initialStart,
  required DateTime initialEnd,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final today = dateOnly(DateTime.now());
  return showDialog<DateTimeRange>(
    context: context,
    builder: (context) => _PersianDateRangeDialog(
      initialStart: dateOnly(initialStart),
      initialEnd: dateOnly(initialEnd),
      firstDate: dateOnly(firstDate ?? today),
      lastDate: dateOnly(
        lastDate ?? DateTime(today.year + 5, today.month, today.day),
      ),
    ),
  );
}

class _PersianDateRangeDialog extends StatefulWidget {
  const _PersianDateRangeDialog({
    required this.initialStart,
    required this.initialEnd,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialStart;
  final DateTime initialEnd;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_PersianDateRangeDialog> createState() =>
      _PersianDateRangeDialogState();
}

class _PersianDateRangeDialogState extends State<_PersianDateRangeDialog> {
  late PersianDate _visibleMonth;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    final initial = PersianDate.fromDateTime(widget.initialStart);
    _visibleMonth = PersianDate(initial.year, initial.month, 1);
  }

  bool _canMove(int delta) {
    final candidate = _visibleMonth.addMonths(delta);
    final monthStart = candidate.toDateTime();
    final monthEnd = PersianDate(
      candidate.year,
      candidate.month,
      candidate.daysInMonth,
    ).toDateTime();
    return !monthEnd.isBefore(widget.firstDate) &&
        !monthStart.isAfter(widget.lastDate);
  }

  void _moveMonth(int delta) {
    if (!_canMove(delta)) return;
    setState(() => _visibleMonth = _visibleMonth.addMonths(delta));
  }

  void _select(DateTime day) {
    if (day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate)) return;
    setState(() {
      if (_start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _start = day;
      } else {
        _end = day;
      }
    });
  }

  void _confirm() {
    final start = _start;
    if (start == null) return;
    Navigator.of(context).pop(DateTimeRange(start: start, end: _end ?? start));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthStart = _visibleMonth.toDateTime();
    final leadingEmptyCells = (monthStart.weekday + 1) % 7;
    final totalCells = leadingEmptyCells + _visibleMonth.daysInMonth;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.date_range_rounded,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'بازه تاریخ کمپین',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'ماه بعد',
                      onPressed: _canMove(1) ? () => _moveMonth(1) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '${PersianDate.monthNames[_visibleMonth.month - 1]} '
                        '${toPersianDigits(_visibleMonth.year)}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'ماه قبل',
                      onPressed: _canMove(-1) ? () => _moveMonth(-1) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  _Weekday('ش'),
                  _Weekday('ی'),
                  _Weekday('د'),
                  _Weekday('س'),
                  _Weekday('چ'),
                  _Weekday('پ'),
                  _Weekday('ج', weekend: true),
                ],
              ),
              const SizedBox(height: 5),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.05,
                ),
                itemCount: totalCells,
                itemBuilder: (context, index) {
                  if (index < leadingEmptyCells) return const SizedBox.shrink();
                  final dayNumber = index - leadingEmptyCells + 1;
                  final day = PersianDate(
                    _visibleMonth.year,
                    _visibleMonth.month,
                    dayNumber,
                  ).toDateTime();
                  return _DayCell(
                    day: day,
                    label: toPersianDigits(dayNumber),
                    enabled:
                        !day.isBefore(widget.firstDate) &&
                        !day.isAfter(widget.lastDate),
                    endpoint: _sameDay(day, _start) || _sameDay(day, _end),
                    inRange: _isInRange(day),
                    today: _sameDay(day, DateTime.now()),
                    onTap: () => _select(day),
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('انصراف'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _start == null ? null : _confirm,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('تأیید بازه'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _selectionLabel {
    final start = _start;
    if (start == null) return 'روز شروع را انتخاب کنید';
    final end = _end;
    if (end == null) return '${formatPersianDate(start)} · حالا پایان را بزنید';
    return formatPersianDateRange(start, end);
  }

  bool _isInRange(DateTime day) {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return false;
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

class _Weekday extends StatelessWidget {
  const _Weekday(this.label, {this.weekend = false});

  final String label;
  final bool weekend;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: weekend ? AppColors.error : AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.label,
    required this.enabled,
    required this.endpoint,
    required this.inRange,
    required this.today,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool enabled;
  final bool endpoint;
  final bool inRange;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = endpoint
        ? AppColors.primary
        : inRange
        ? AppColors.primary.withValues(alpha: 0.12)
        : Colors.transparent;
    return Semantics(
      button: true,
      enabled: enabled,
      label: formatPersianDate(day),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          margin: const EdgeInsets.all(2.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: today && !endpoint
                ? Border.all(color: AppColors.secondary)
                : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: !enabled
                  ? AppColors.textSecondary.withValues(alpha: 0.35)
                  : endpoint
                  ? const Color(0xFF00382E)
                  : AppColors.textPrimary,
              fontWeight: endpoint || today ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

bool _sameDay(DateTime day, DateTime? other) {
  return other != null &&
      day.year == other.year &&
      day.month == other.month &&
      day.day == other.day;
}
