import 'package:flutter/material.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/home/presentation/widgets/log_tile.dart';
import 'package:untitled3/features/logs/domain/log_entry.dart';

enum LogFilter { all, codes, connection, issues }

class ActivityTab extends StatelessWidget {
  const ActivityTab({
    super.key,
    required this.logs,
    required this.filter,
    required this.expandedIds,
    required this.onFilterChanged,
    required this.onToggleExpanded,
    required this.onCopyOne,
    required this.onCopyAll,
    required this.onClear,
  });

  final List<LogEntry> logs;
  final LogFilter filter;
  final Set<int> expandedIds;
  final ValueChanged<LogFilter> onFilterChanged;
  final ValueChanged<int> onToggleExpanded;
  final ValueChanged<LogEntry> onCopyOne;
  final VoidCallback onCopyAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issues = logs.where(_isIssue).length;
    final visibleLogs = logs.where((entry) => _matches(entry, filter)).toList();

    return CustomScrollView(
      key: const PageStorageKey('activity-tab'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActivitySummary(
                  total: logs.length,
                  issues: issues,
                  onCopyAll: logs.isEmpty ? null : onCopyAll,
                  onClear: logs.isEmpty ? null : onClear,
                ),
                const SizedBox(height: 16),
                Text(
                  'فیلتر گزارش',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: LogFilter.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = LogFilter.values[index];
                      return ChoiceChip(
                        avatar: Icon(_filterIcon(item), size: 17),
                        label: Text(_filterLabel(item, issues)),
                        selected: filter == item,
                        onSelected: (_) => onFilterChanged(item),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
        if (visibleLogs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyActivity(hasLogs: logs.isNotEmpty),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.builder(
              itemCount: visibleLogs.length,
              itemBuilder: (context, index) {
                final entry = visibleLogs[index];
                return LogTile(
                  key: ValueKey(entry.id),
                  entry: entry,
                  expanded: expandedIds.contains(entry.id),
                  onTap: () => onToggleExpanded(entry.id),
                  onLongPress: () => onCopyOne(entry),
                );
              },
            ),
          ),
      ],
    );
  }

  static bool _isIssue(LogEntry entry) {
    return entry.level == LogLevel.error || entry.level == LogLevel.warning;
  }

  static bool _matches(LogEntry entry, LogFilter filter) {
    return switch (filter) {
      LogFilter.all => true,
      LogFilter.codes => entry.kind == LogKind.flow,
      LogFilter.connection =>
        entry.kind == LogKind.request || entry.kind == LogKind.response,
      LogFilter.issues => _isIssue(entry),
    };
  }

  static String _filterLabel(LogFilter filter, int issues) {
    return switch (filter) {
      LogFilter.all => 'همه',
      LogFilter.codes => 'کدها',
      LogFilter.connection => 'اتصال',
      LogFilter.issues => issues > 0 ? 'خطاها ($issues)' : 'خطاها',
    };
  }

  static IconData _filterIcon(LogFilter filter) {
    return switch (filter) {
      LogFilter.all => Icons.view_list_rounded,
      LogFilter.codes => Icons.sms_rounded,
      LogFilter.connection => Icons.cloud_sync_rounded,
      LogFilter.issues => Icons.warning_amber_rounded,
    };
  }
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({
    required this.total,
    required this.issues,
    required this.onCopyAll,
    required this.onClear,
  });

  final int total;
  final int issues;
  final VoidCallback? onCopyAll;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total رویداد ذخیره‌شده',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  issues > 0
                      ? '$issues مورد نیاز به بررسی دارد'
                      : 'خطای فعالی در گزارش‌ها دیده نمی‌شود',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: issues > 0
                        ? AppColors.warning
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'کپی کل گزارش',
            onPressed: onCopyAll,
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            tooltip: 'پاک کردن گزارش',
            onPressed: onClear,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.hasLogs});

  final bool hasLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasLogs ? Icons.filter_alt_off_rounded : Icons.inbox_rounded,
                size: 34,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              hasLogs ? 'موردی با این فیلتر نیست' : 'هنوز فعالیتی ثبت نشده',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasLogs
                  ? 'فیلتر دیگری را انتخاب کنید'
                  : 'پس از شروع سرویس، دریافت و ارسال‌ها اینجا نمایش داده می‌شوند',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
