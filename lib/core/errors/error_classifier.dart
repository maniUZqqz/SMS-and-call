import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sms_bridge/sms_bridge.dart';

class ErrorInfo {
  final String title;
  final String hint;
  final String technical;

  /// خطایی که با تکرار سریع درست نمی‌شود (مثلاً شماره نامعتبر)؛ تلاش بعدی با فاصله‌ی زیاد
  final bool permanent;

  const ErrorInfo(
    this.title,
    this.hint,
    this.technical, {
    this.permanent = false,
  });
}

class ErrorClassifier {
  static String describe(Object e) {
    final s = '${e.runtimeType}: $e';
    return s.length > 400 ? '${s.substring(0, 400)}…' : s;
  }

  static ErrorInfo network(Object e) {
    final low = e.toString().toLowerCase();
    final tech = describe(e);

    if (e is TimeoutException ||
        low.contains('timed out') ||
        low.contains('timeout')) {
      return ErrorInfo(
        'سرور پاسخ نداد (Timeout)',
        'سرور روشن است و گوشی به همان شبکه وصل است؟ فایروال سرور را هم بررسی کنید.',
        tech,
      );
    }
    if (low.contains('cleartext')) {
      return ErrorInfo(
        'اندروید اجازه اتصال http نمی‌دهد',
        'در AndroidManifest مقدار usesCleartextTraffic را true کنید یا از https استفاده کنید.',
        tech,
      );
    }
    if (low.contains('connection refused') ||
        low.contains('errno = 111') ||
        low.contains('errno = 61')) {
      return ErrorInfo(
        'سرور اتصال را رد کرد',
        'برنامه سرور روی این پورت اجرا نیست، یا آدرس/پورت اشتباه است.',
        tech,
      );
    }
    if (low.contains('failed host lookup') ||
        low.contains('nodename nor servname')) {
      return ErrorInfo(
        'آدرس سرور پیدا نشد',
        'آدرس را در تنظیمات بررسی کنید و مطمئن شوید شبکه وصل است.',
        tech,
      );
    }
    if (low.contains('network is unreachable') ||
        low.contains('no route to host') ||
        low.contains('errno = 101') ||
        low.contains('errno = 113')) {
      return ErrorInfo(
        'شبکه سرور در دسترس نیست',
        'Wi-Fi یا هات‌اسپات را بررسی کنید؛ گوشی و سرور باید در یک شبکه باشند.',
        tech,
      );
    }
    if (low.contains('connection reset') ||
        low.contains('broken pipe') ||
        low.contains('connection closed') ||
        low.contains('software caused')) {
      return ErrorInfo(
        'ارتباط با سرور قطع شد',
        'سرور ری‌استارت شده یا اتصال ناپایدار است.',
        tech,
      );
    }
    if (e is HandshakeException ||
        e is TlsException ||
        low.contains('handshake') ||
        low.contains('certificate')) {
      return ErrorInfo(
        'خطای امنیتی SSL',
        'گواهی سرور معتبر نیست؛ از http استفاده کنید یا گواهی را اصلاح کنید.',
        tech,
      );
    }
    if (e is SocketException || e is http.ClientException) {
      return ErrorInfo(
        'خطای شبکه',
        'اتصال گوشی و سرور را بررسی کنید. جزئیات فنی را ببینید.',
        tech,
      );
    }
    return ErrorInfo(
      'خطای ناشناخته در ارتباط',
      'جزئیات فنی را ببینید و اگر تکرار شد گزارش را کپی کنید.',
      tech,
    );
  }

  static ErrorInfo httpStatus(int code) {
    switch (code) {
      case 400:
        return const ErrorInfo(
          'درخواست نامعتبر (400)',
          'فرمت داده ارسالی با انتظار سرور هماهنگ نیست.',
          '',
        );
      case 401:
      case 403:
        return ErrorInfo(
          'دسترسی رد شد ($code)',
          'احراز هویت یا IP مجاز در سرور را بررسی کنید.',
          '',
        );
      case 404:
        return const ErrorInfo(
          'مسیر API پیدا نشد (404)',
          'مسیر را در تنظیمات سرور بررسی کنید.',
          '',
        );
      case 405:
        return const ErrorInfo(
          'متد درخواست مجاز نیست (405)',
          'سرور این مسیر را با این متد (GET/POST) قبول نمی‌کند.',
          '',
        );
      case 408:
      case 504:
        return ErrorInfo(
          'سرور دیر پاسخ داد ($code)',
          'سرور بیش از حد مشغول است یا پشت پراکسی قطع شده.',
          '',
        );
      case 429:
        return const ErrorInfo(
          'تعداد درخواست بیش از حد مجاز (429)',
          'سرور محدودیت نرخ دارد؛ کمی صبر کنید.',
          '',
        );
      default:
        if (code >= 500) {
          return ErrorInfo(
            'خطای داخلی سرور ($code)',
            'مشکل از سمت سرور است؛ لاگ سرور را بررسی کنید.',
            '',
          );
        }
        return ErrorInfo(
          'پاسخ غیرمنتظره از سرور ($code)',
          'کد وضعیت مورد انتظار ۲۰۰ است.',
          '',
        );
    }
  }

  /// خطاهای مبتنی بر متن استثنا (PlatformException، MissingPlugin و …)
  static ErrorInfo sms(Object e) {
    final low = e.toString().toLowerCase();
    final tech = describe(e);
    if (e is MissingPluginException || low.contains('missingplugin')) {
      return ErrorInfo(
        'افزونه بومی پیامک پیدا نشد',
        'پروژه را یک‌بار flutter clean کنید و دوباره build بگیرید (و مطمئن شوید sms_bridge در pubspec هست).',
        tech,
      );
    }
    if (low.contains('permission') || low.contains('securityexception')) {
      return ErrorInfo(
        'مجوز ارسال پیامک داده نشده',
        'از «بررسی مجوزها» مجوز پیامک را فعال کنید. در اندروید ۱۳+ ممکن است لازم باشد «Allow restricted settings» را از تنظیمات برنامه روشن کنید.',
        tech,
      );
    }
    if (low.contains('illegalargument') || low.contains('invalid')) {
      return ErrorInfo(
        'شماره یا متن پیامک نامعتبر است',
        'فرمت شماره گیرنده را در سرور بررسی کنید.',
        tech,
        permanent: true,
      );
    }
    return ErrorInfo(
      'ارسال پیامک ناموفق بود',
      'سیم‌کارت، آنتن‌دهی و محدودیت ارسال پیامک اندروید/اپراتور را بررسی کنید.',
      tech,
    );
  }

  /// نتیجه‌ی ساختاریافته‌ی لایه‌ی بومی
  static ErrorInfo smsResult(SmsSendResult r) {
    final modem = r.modemCode >= 0 ? ' · modem=${r.modemCode}' : '';
    final tech =
        'code=${r.code}$modem · parts=${r.partsOk}/${r.parts} · subId=${r.subId}'
        '${r.error.isNotEmpty ? '\n${r.error}' : ''}';

    ErrorInfo mk(String t, String h, {bool permanent = false}) =>
        ErrorInfo(t, h, tech, permanent: permanent);

    switch (r.code) {
      case 1:
        return mk(
          'ارسال توسط اپراتور/مودم رد شد',
          'اعتبار، آنتن‌دهی و فعال بودن سرویس پیامک سیم‌کارت را بررسی کنید. اگر سیم‌کارت دیگری دارید آن را از تنظیمات پیامک امتحان کنید.',
        );
      case 2:
        return mk('رادیوی موبایل خاموش است', 'حالت پرواز را خاموش کنید.');
      case 3:
        return mk(
          'ساخت بسته‌ی پیامک (PDU) ناموفق بود',
          'شماره یا متن را بررسی کنید؛ کاراکتر غیرمعمول در متن ممکن است باعث این خطا شود.',
          permanent: true,
        );
      case 4:
        return mk(
          'سیم‌کارت آنتن‌دهی ندارد',
          'آنتن و ثبت‌نام شبکه‌ی سیم‌کارت انتخاب‌شده را بررسی کنید یا سیم‌کارت دیگری انتخاب کنید.',
        );
      case 5:
        return mk(
          'سقف ارسال پیامک پر شد',
          'اندروید یا اپراتور تعداد پیامک ارسالی را محدود کرده؛ کمی صبر کنید یا از سیم‌کارت دیگر استفاده کنید.',
        );
      case 6:
        return mk(
          'شماره توسط FDN سیم‌کارت مسدود است',
          'قابلیت «شماره‌های مجاز (FDN)» سیم‌کارت فعال است؛ آن را خاموش کنید.',
          permanent: true,
        );
      case 7:
      case 8:
        return mk(
          'ارسال به شماره‌ی کوتاه/ویژه مجاز نیست',
          'اندروید ارسال به این نوع شماره را مسدود کرده است.',
          permanent: true,
        );
      case 9:
        return mk(
          'رادیوی موبایل در دسترس نیست',
          'گوشی را یک‌بار ری‌استارت یا حالت پرواز را روشن/خاموش کنید.',
        );
      case 10:
        return mk(
          'شبکه ارسال را رد کرد',
          'اپراتور پیامک را نپذیرفت؛ اعتبار و محدودیت‌های خط را بررسی کنید.',
        );
      case 11:
        return mk(
          'پارامتر ارسال نامعتبر است',
          'شماره‌ی گیرنده را بررسی کنید.',
          permanent: true,
        );
      case 12:
        return mk(
          'وضعیت مودم برای ارسال مناسب نیست',
          'چند ثانیه صبر کنید؛ تلاش خودکار تکرار می‌شود.',
        );
      case 13:
        return mk(
          'حافظه‌ی مودم/سیم‌کارت پر است',
          'پیامک‌های قدیمی سیم‌کارت را پاک کنید.',
        );
      case 14:
        return mk(
          'قالب پیامک نامعتبر است',
          'متن یا شماره را بررسی کنید.',
          permanent: true,
        );
      case 15:
      case 21:
        return mk(
          'خطای داخلی سیستم اندروید',
          'گوشی را ری‌استارت کنید؛ اگر تکرار شد جزئیات فنی را بفرستید.',
        );
      case 16:
        return mk(
          'خطای مودم',
          'گوشی را ری‌استارت کنید یا سیم‌کارت را یک‌بار خارج و جا بزنید.',
        );
      case 17:
        return mk(
          'خطای شبکه‌ی موبایل',
          'آنتن‌دهی را بررسی کنید؛ تلاش خودکار تکرار می‌شود.',
        );
      case 18:
        return mk(
          'شماره‌ی مرکز پیامک (SMSC) نامعتبر است',
          'مرکز پیامک سیم‌کارت تنظیم نیست؛ با اپراتور تماس بگیرید یا سیم‌کارت دیگر را امتحان کنید.',
        );
      case 19:
        return mk(
          'عملیات توسط سیستم مجاز نشد',
          'محدودیت‌های والدین/سازمانی یا برنامه‌ی امنیتی گوشی را بررسی کنید.',
        );
      case 22:
        return mk(
          'منابع سیستم برای ارسال کافی نیست',
          'کمی صبر کنید؛ تلاش خودکار تکرار می‌شود.',
        );
      case 23:
        return mk('ارسال لغو شد', 'تلاش بعدی خودکار انجام می‌شود.');
      case 24:
        return mk(
          'این گوشی/سیم‌کارت از این نوع ارسال پشتیبانی نمی‌کند',
          'سیم‌کارت دیگری را انتخاب کنید.',
        );
      case 29:
        return mk(
          'ارسال پیامک در حالت اضطراری مسدود است',
          'بعد از پایان حالت اضطراری دوباره تلاش می‌شود.',
        );
      case 30:
        return mk(
          'تلاش مجدد سیستم برای ارسال شکست خورد',
          'آنتن و اعتبار را بررسی کنید.',
        );
      case 31:
        return mk(
          'ارتباط با سرویس تلفن گوشی قطع شد',
          'گوشی را ری‌استارت کنید.',
        );
      case 32:
        return mk(
          'برنامه‌ی پیش‌فرض پیامک تعریف نشده',
          'یک برنامه‌ی پیامک را در تنظیمات اندروید به‌عنوان پیش‌فرض انتخاب کنید.',
        );
      case -100:
        return mk(
          'گزارش ارسال از سیستم نرسید (Timeout)',
          'ممکن است آنتن ضعیف باشد یا سازنده‌ی گوشی ارسال پیامک را در پس‌زمینه محدود کرده باشد.',
        );
      case -101:
        return mk(
          'سیم‌کارت انتخاب‌شده در گوشی فعال نیست',
          'سیم‌کارت را جا بزنید یا از «تنظیمات پیامک» سیم‌کارت دیگری انتخاب کنید.',
        );
      case -102:
        return sms(r.error.isEmpty ? 'unknown native error' : r.error);
      case -103:
        return mk(
          'مجوز ارسال پیامک داده نشده',
          'از «بررسی مجوزها» مجوز پیامک را فعال کنید. در اندروید ۱۳+ ممکن است لازم باشد «Allow restricted settings» را از تنظیمات برنامه روشن کنید.',
        );
      case -104:
        return mk(
          'این دستگاه قابلیت پیامک (تلفن) ندارد',
          'برنامه را روی گوشی دارای سیم‌کارت اجرا کنید.',
          permanent: true,
        );
      case -105:
        return mk(
          'شماره یا متن پیامک خالی است',
          'داده‌ی ارسالی سرور را بررسی کنید.',
          permanent: true,
        );
      case -106:
        return mk(
          'افزونه بومی پیامک پیدا نشد',
          'پروژه را flutter clean کنید و دوباره build بگیرید (و مطمئن شوید sms_bridge در pubspec هست).',
        );
      default:
        return mk(
          'ارسال پیامک ناموفق بود (کد ${r.code})',
          'سیم‌کارت، آنتن‌دهی و محدودیت ارسال پیامک اندروید/اپراتور را بررسی کنید.',
        );
    }
  }
}
