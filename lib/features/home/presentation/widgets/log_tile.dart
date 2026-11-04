import 'package:flutter/material.dart';
import 'package:untitled3/features/logs/domain/log_entry.dart';
import 'package:untitled3/features/logs/presentation/log_style.dart';

class LogTile extends StatelessWidget {
  const LogTile({
    super.key,
    required this.entry,
    required this.expanded,
    required this.onTap,
    required this.onLongPress,
  });

  final LogEntry entry;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const TextStyle _mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11.5,
    height: 1.45,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final level = entry.level;
    final color = levelColor(level, cs);
    final problem = level == LogLevel.error || level == LogLevel.warning;

    final hint = entry.primaryHint;
    final detail = entry.primaryDetail;

    IconData leading = kindIcon(entry.kind);

    if (level == LogLevel.error) {
      leading = Icons.error_rounded;
    }

    if (level == LogLevel.warning) {
      leading = Icons.warning_amber_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 10, 10),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(leading, size: 17, color: color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.title,
                                  maxLines: expanded ? null : 2,
                                  overflow: expanded
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _tag(cs),
                                    Text(
                                      fmtTime(entry.time),
                                      textDirection: TextDirection.ltr,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.outline,
                                            fontSize: 11.5,
                                          ),
                                    ),
                                    if (entry.count > 1)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          '×${entry.count}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: cs.outline,
                          ),
                        ],
                      ),
                      if (problem && detail != null && !expanded)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            detail,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      if (problem && hint != null && !expanded)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            hint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              color: color,
                              height: 1.45,
                            ),
                          ),
                        ),
                      if (entry.steps.isNotEmpty && !expanded)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              for (final s in entry.steps)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      stepIcon(s.state),
                                      size: 14,
                                      color: stepColor(s.state, cs),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      s.label,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(fontSize: 11.5),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      if (expanded) ..._expandedChildren(theme, color),
                    ],
                  ),
                ),
              ),
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kindIcon(entry.kind), size: 12, color: cs.outline),
          const SizedBox(width: 3),
          Text(
            kindLabel(entry.kind),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  List<Widget> _expandedChildren(ThemeData theme, Color color) {
    final cs = theme.colorScheme;

    final w = <Widget>[
      const SizedBox(height: 8),
      Divider(height: 1, color: cs.outlineVariant),
    ];

    for (final s in entry.steps) {
      w.add(_stepRow(theme, s));
    }

    if (entry.detail != null) {
      w.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            entry.detail!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ),
      );
    }

    if (entry.hint != null) {
      w.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            entry.hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: color,
              height: 1.45,
            ),
          ),
        ),
      );
    }

    entry.meta.forEach((k, v) {
      w.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: Text(
                  k,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.outline,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  v,
                  textDirection: dirFor(v),
                  style: _mono,
                ),
              ),
            ],
          ),
        ),
      );
    });

    if (entry.tech != null) {
      w.add(_techBlock(cs, entry.tech!));
    }

    return w;
  }

  Widget _stepRow(ThemeData theme, FlowStep s) {
    final cs = theme.colorScheme;
    final c = stepColor(s.state, cs);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(stepIcon(s.state), size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Text(
                      fmtTime(s.time),
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.outline,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (s.detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      s.detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (s.hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      s.hint!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        color: c,
                        height: 1.45,
                      ),
                    ),
                  ),
                if (s.tech != null) _techBlock(cs, s.tech!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _techBlock(ColorScheme cs, String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(text, textDirection: dirFor(text), style: _mono),
    );
  }
}
