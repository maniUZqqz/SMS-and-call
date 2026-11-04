enum LogLevel { info, success, warning, error }

enum LogKind { system, request, response, flow }

enum StepState { pending, ok, warn, fail }

T _enumAt<T>(List<T> values, dynamic i, T fallback) {
  if (i is int && i >= 0 && i < values.length) return values[i];
  return fallback;
}

String fmtTime(DateTime n) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
}

String kindLabel(LogKind k) {
  switch (k) {
    case LogKind.system:
      return 'سیستم';
    case LogKind.request:
      return 'درخواست به سرور';
    case LogKind.response:
      return 'پاسخ سرور';
    case LogKind.flow:
      return 'ارسال کد';
  }
}

class FlowStep {
  String label;
  StepState state;
  String? detail;
  String? hint;
  String? tech;
  DateTime time;

  FlowStep(
    this.label, {
    this.state = StepState.pending,
    this.detail,
    this.hint,
    this.tech,
  }) : time = DateTime.now();

  void update(StepState s, {String? detail, String? hint, String? tech}) {
    state = s;
    this.detail = detail;
    this.hint = hint;
    this.tech = tech;
    time = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'state': state.index,
    'detail': detail,
    'hint': hint,
    'tech': tech,
    't': time.millisecondsSinceEpoch,
  };

  factory FlowStep.fromJson(Map<String, dynamic> j) {
    final s = FlowStep(
      (j['label'] ?? '').toString(),
      state: _enumAt(StepState.values, j['state'], StepState.pending),
      detail: j['detail'] as String?,
      hint: j['hint'] as String?,
      tech: j['tech'] as String?,
    );
    final t = j['t'];
    if (t is int) s.time = DateTime.fromMillisecondsSinceEpoch(t);
    return s;
  }
}

class LogEntry {
  static int _lastId = 0;
  static int _nextId() {
    final n = DateTime.now().microsecondsSinceEpoch;
    _lastId = n > _lastId ? n : _lastId + 1;
    return _lastId;
  }

  final int id;
  DateTime time;
  final LogKind kind;
  final LogLevel _baseLevel;
  String title;
  String? detail;
  String? hint;
  String? tech;
  Map<String, String> meta;
  int count;
  final String? dedupeKey;
  final List<FlowStep> steps;

  LogEntry({
    int? id,
    required this.kind,
    LogLevel level = LogLevel.info,
    required this.title,
    this.detail,
    this.hint,
    this.tech,
    Map<String, String>? meta,
    this.dedupeKey,
    List<FlowStep>? steps,
  }) : id = id ?? _nextId(),
       _baseLevel = level,
       time = DateTime.now(),
       count = 1,
       meta = meta ?? <String, String>{},
       steps = steps ?? <FlowStep>[];

  LogLevel get level {
    if (steps.isEmpty) return _baseLevel;
    if (steps.any((s) => s.state == StepState.fail)) return LogLevel.error;
    if (steps.any((s) => s.state == StepState.warn)) return LogLevel.warning;
    if (steps.every((s) => s.state == StepState.ok)) return LogLevel.success;
    return LogLevel.info;
  }

  String? get primaryHint {
    if (hint != null) return hint;
    for (final s in steps) {
      if ((s.state == StepState.fail || s.state == StepState.warn) &&
          s.hint != null) {
        return s.hint;
      }
    }
    return null;
  }

  String? get primaryDetail {
    if (detail != null) return detail;
    for (final s in steps) {
      if ((s.state == StepState.fail || s.state == StepState.warn) &&
          s.detail != null) {
        return s.detail;
      }
    }
    return null;
  }

  String get flowSummary {
    for (final s in steps) {
      if (s.state == StepState.fail) return 'خطا در «${s.label}»';
    }
    for (final s in steps) {
      if (s.state == StepState.pending) return 'در حال «${s.label}»';
    }
    if (steps.any((s) => s.state == StepState.warn)) {
      return 'انجام شد (با هشدار)';
    }
    return 'با موفقیت انجام شد';
  }

  String get notificationText {
    if (kind == LogKind.flow) return '$title · $flowSummary';
    return count > 1 ? '$title ×$count' : title;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    't': time.millisecondsSinceEpoch,
    'kind': kind.index,
    'level': _baseLevel.index,
    'title': title,
    'detail': detail,
    'hint': hint,
    'tech': tech,
    'meta': meta,
    'count': count,
    'dk': dedupeKey,
    'steps': steps.map((s) => s.toJson()).toList(),
  };

  factory LogEntry.fromJson(Map<String, dynamic> j) {
    final metaRaw = j['meta'];
    final stepsRaw = j['steps'];
    final e = LogEntry(
      id: j['id'] as int,
      kind: _enumAt(LogKind.values, j['kind'], LogKind.system),
      level: _enumAt(LogLevel.values, j['level'], LogLevel.info),
      title: (j['title'] ?? '').toString(),
      detail: j['detail'] as String?,
      hint: j['hint'] as String?,
      tech: j['tech'] as String?,
      dedupeKey: j['dk'] as String?,
      meta: metaRaw is Map
          ? metaRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
          : <String, String>{},
      steps: stepsRaw is List
          ? stepsRaw
                .map(
                  (s) => FlowStep.fromJson(Map<String, dynamic>.from(s as Map)),
                )
                .toList()
          : <FlowStep>[],
    );
    final t = j['t'];
    if (t is int) e.time = DateTime.fromMillisecondsSinceEpoch(t);
    final c = j['count'];
    if (c is int) e.count = c;
    return e;
  }

  String toPlainText() {
    const lv = {
      LogLevel.info: 'INFO',
      LogLevel.success: 'OK',
      LogLevel.warning: 'WARN',
      LogLevel.error: 'ERROR',
    };
    const st = {
      StepState.pending: '...',
      StepState.ok: 'OK',
      StepState.warn: 'WARN',
      StepState.fail: 'FAIL',
    };
    final b = StringBuffer();
    b.writeln(
      '[${fmtTime(time)}] ${lv[level]} | ${kindLabel(kind)} | $title${count > 1 ? '  (×$count)' : ''}',
    );
    if (detail != null) b.writeln('    $detail');
    if (hint != null) b.writeln('    راهنما: $hint');
    meta.forEach((k, v) => b.writeln('    $k: $v'));
    if (tech != null) {
      b.writeln('    فنی: ${tech!.replaceAll('\n', '\n        ')}');
    }
    for (final s in steps) {
      b.writeln('    - [${st[s.state]}] ${s.label}: ${s.detail ?? ''}');
      if (s.hint != null) b.writeln('        راهنما: ${s.hint}');
      if (s.tech != null) {
        b.writeln('        فنی: ${s.tech!.replaceAll('\n', '\n            ')}');
      }
    }
    return b.toString().trimRight();
  }
}
