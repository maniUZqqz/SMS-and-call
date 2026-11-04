import 'package:flutter_test/flutter_test.dart';
import 'package:untitled3/features/logs/domain/log_entry.dart';

void main() {
  test('LogEntry preserves a flow when serialized and restored', () {
    final entry = LogEntry(
      id: 42,
      kind: LogKind.flow,
      title: 'کد تایید برای 09120000000',
      meta: {'شناسه': 'otp-1'},
      steps: [
        FlowStep('دریافت از سرور', state: StepState.ok),
        FlowStep(
          'ارسال پیامک',
          state: StepState.warn,
          detail: 'در انتظار تلاش بعدی',
        ),
      ],
    );

    final restored = LogEntry.fromJson(entry.toJson());

    expect(restored.id, 42);
    expect(restored.kind, LogKind.flow);
    expect(restored.level, LogLevel.warning);
    expect(restored.meta, {'شناسه': 'otp-1'});
    expect(restored.steps, hasLength(2));
    expect(restored.steps.last.detail, 'در انتظار تلاش بعدی');
  });
}
