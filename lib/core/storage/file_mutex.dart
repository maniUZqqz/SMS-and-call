import 'dart:async';
import 'dart:io';

/// قفل برای نوشتن هم‌زمانِ چند ایزوله (رابط کاربری + سرویس پس‌زمینه) روی یک فایل.
///
/// `RandomAccessFile.lock` برای این کار کافی نیست: قفل‌های فایل در اندروید/لینوکس
/// «به‌ازای فرایند» هستند و دو ایزولهٔ هم‌فرایند همدیگر را بیرون نمی‌کنند؛ در نتیجه
/// نوشتنِ هم‌زمان (مثلاً ذخیرهٔ کمپین از صفحه، هم‌زمان با ثبت نتیجهٔ ارسال در سرویس)
/// تغییرِ یکی را بی‌صدا از بین می‌برد. اینجا از ساخت انحصاری فایل (O_EXCL، اتمیک) استفاده
/// می‌شود، و داخل یک ایزوله هم عملیات‌ها پشت سر هم صف می‌شوند.
class FileMutex {
  FileMutex(
    this.path, {
    this.staleAfter = const Duration(seconds: 15),
    this.timeout = const Duration(seconds: 20),
    this.retryEvery = const Duration(milliseconds: 25),
  });

  final String path;

  /// قفلِ قدیمی‌تر از این مدت، رهاشده فرض می‌شود (فرایندی که وسط کار مرده).
  final Duration staleAfter;

  /// بیشینهٔ انتظار؛ بعد از آن قفل شکسته می‌شود تا برنامه برای همیشه گیر نکند.
  final Duration timeout;
  final Duration retryEvery;

  static final Map<String, Future<void>> _queues = <String, Future<void>>{};
  static int _tokenCounter = 0;

  Future<T> synchronized<T>(Future<T> Function() action) async {
    final previous = _queues[path] ?? Future<void>.value();
    final gate = Completer<void>();
    final mine = gate.future;
    _queues[path] = mine;
    await previous;
    final file = File(path);
    final token = '${DateTime.now().microsecondsSinceEpoch}-${_tokenCounter++}';
    try {
      await _acquire(file, token);
      try {
        return await action();
      } finally {
        // فقط اگر قفل هنوز مالِ ماست پاکش کن (ممکن است به‌خاطر کهنگی شکسته و دست دیگری افتاده باشد)
        try {
          if (await file.exists() && await file.readAsString() == token) {
            await file.delete();
          }
        } catch (_) {}
      }
    } finally {
      gate.complete();
      if (identical(_queues[path], mine)) _queues.remove(path);
    }
  }

  Future<void> _acquire(File file, String token) async {
    final deadline = DateTime.now().add(timeout);
    var attempts = 0;
    while (true) {
      attempts++;
      try {
        await file.create(exclusive: true);
        await file.writeAsString(token, flush: true);
        return;
      } on FileSystemException {
        // قفل دست کس دیگری است (یا دیسک مشکل دارد)
      }
      try {
        final age = DateTime.now().difference(await file.lastModified());
        if (age > staleAfter) {
          await file.delete();
          continue;
        }
      } on FileSystemException {
        // قفل وسط بررسی آزاد شد، یا پوشه قابل دسترس نیست؛ به انتظار و بررسی مهلت می‌رویم
      }
      if (DateTime.now().isAfter(deadline)) {
        // مهلت تمام شد: قفل را می‌شکنیم تا برنامه گیر نکند. اگر بعد از شکستن هم نشد
        // (دیسک پر/بدون دسترسی)، به‌جای چرخش بی‌پایان، بدون قفل ادامه می‌دهیم.
        try {
          await file.delete();
        } catch (_) {}
        if (attempts > 3) {
          try {
            await file.create(exclusive: true);
            await file.writeAsString(token, flush: true);
          } on FileSystemException {
            return;
          }
          return;
        }
      }
      await Future<void>.delayed(retryEvery);
    }
  }
}
