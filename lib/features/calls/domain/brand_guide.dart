import 'package:sms_and_call/features/calls/domain/recording_matcher.dart';

/// راهنمای فعال کردن ضبط خودکار تماس در خودِ گوشی، به تفکیک برند. منوها در نسخه‌های
/// مختلف کمی فرق می‌کنند؛ متن‌ها «بهترین تلاش» هستند و با نام فارسی/انگلیسی منو آمده‌اند.
class BrandGuide {
  const BrandGuide({
    required this.brand,
    required this.title,
    required this.steps,
    required this.folderHint,
    required this.canWatchFolder,
    this.caveat = '',
  });

  final RecorderBrand brand;
  final String title;

  /// مراحل فعال کردن ضبط خودکار تماس در برنامه‌ی «Phone / تلفن» گوشی.
  final List<String> steps;

  /// جایی که گوشی فایل‌ها را ذخیره می‌کند.
  final String folderHint;

  /// آیا برنامه می‌تواند این پوشه را بخواند؟ (گوگل‌دایلر نه)
  final bool canWatchFolder;

  /// محدودیت‌ها و هشدارهای این برند.
  final String caveat;
}

const List<BrandGuide> kBrandGuides = [
  BrandGuide(
    brand: RecorderBrand.samsung,
    title: 'سامسونگ (One UI)',
    steps: [
      'برنامه‌ی «Phone / تلفن» گوشی را باز کنید.',
      'روی منوی سه‌نقطه (⋮) بالا بزنید و «Settings / تنظیمات» را انتخاب کنید.',
      'گزینه‌ی «Record calls / ضبط تماس‌ها» را باز کنید.',
      'کلید «Auto record calls / ضبط خودکار تماس‌ها» را روشن کنید و «All calls / همه‌ی تماس‌ها» را انتخاب کنید.',
      'اگر «ضبط تماس» در منو نیست، در بعضی کشورها سامسونگ آن را حذف کرده است؛ از «ضبط‌کننده‌ی داخلی» (دسترس‌پذیری) در همین برنامه استفاده کنید.',
    ],
    folderHint: 'حافظه ← Recordings ← Call (برنامه‌ی My Files)',
    canWatchFolder: true,
    caveat:
        'روی سامسونگِ اندروید ۱۱ به بعد این روش مطمئن‌ترین راه است. در بعضی مدل‌ها/کشورها گزینه‌ی ضبط تماس غیرفعال است.',
  ),
  BrandGuide(
    brand: RecorderBrand.xiaomi,
    title: 'شیائومی / ردمی / پوکو (MIUI و HyperOS)',
    steps: [
      'برنامه‌ی «Phone / تلفن» را باز کنید.',
      'روی منوی سه‌خط یا چرخ‌دنده‌ی تنظیمات بالا بزنید.',
      'گزینه‌ی «Call recording / ضبط تماس» را باز کنید.',
      'کلید «Record calls automatically / ضبط خودکار تماس‌ها» را روشن کنید و «All numbers / همه‌ی شماره‌ها» را انتخاب کنید.',
      'اگر به‌جای برنامه‌ی تلفن شیائومی، «Google Phone» نصب است، ضبط در پوشه‌ی خصوصی گوگل می‌ماند و برنامه نمی‌تواند آن را بخواند؛ از «ضبط‌کننده‌ی داخلی» استفاده کنید.',
    ],
    folderHint: 'حافظه ← MIUI ← sound_recorder ← call_rec',
    canWatchFolder: true,
    caveat:
        'در ROM جهانی (Global) بعضی مدل‌ها شماره‌گیر گوگل دارند و ضبط خودکار ندارند.',
  ),
  BrandGuide(
    brand: RecorderBrand.huawei,
    title: 'هواوی / آنر (EMUI و MagicOS)',
    steps: [
      'برنامه‌ی «Phone / تلفن» را باز کنید.',
      'روی سه‌نقطه (⋮) ← «Settings / تنظیمات» بزنید.',
      'گزینه‌ی «Call recording / ضبط تماس» را باز کنید.',
      'کلید «Record calls automatically / ضبط خودکار» را روشن کنید و «All calls / همه‌ی تماس‌ها» را انتخاب کنید.',
    ],
    folderHint: 'حافظه ← Sounds ← CallRecord (یا Recordings ← Call recordings)',
    canWatchFolder: true,
    caveat: 'در بعضی نسخه‌های جدید و برخی بازارها ضبط تماس حذف شده است.',
  ),
  BrandGuide(
    brand: RecorderBrand.oppo,
    title: 'اوپو / ریلمی / وان‌پلاس (ColorOS، realme UI، OxygenOS)',
    steps: [
      'برنامه‌ی «Phone / تلفن» را باز کنید.',
      'روی منوی سه‌نقطه یا چرخ‌دنده ← «Settings / تنظیمات» بزنید.',
      'گزینه‌ی «Call recording / ضبط تماس» را باز کنید.',
      'کلید «Record all calls automatically / ضبط خودکار همه‌ی تماس‌ها» را روشن کنید.',
      'در وان‌پلاسِ جهانی که «Google Phone» دارد این گزینه نیست؛ از «ضبط‌کننده‌ی داخلی» استفاده کنید.',
    ],
    folderHint: 'حافظه ← Music ← Recordings ← Call Recordings (یا Recordings ← Call Recordings)',
    canWatchFolder: true,
  ),
  BrandGuide(
    brand: RecorderBrand.vivo,
    title: 'ویوو / آی‌کیو (Funtouch و OriginOS)',
    steps: [
      'برنامه‌ی «Phone / تلفن» را باز کنید.',
      'روی منوی سه‌نقطه یا «Settings / تنظیمات» بزنید و «Call recording / ضبط تماس» را پیدا کنید.',
      'گزینه‌ی «Auto record / ضبط خودکار» را روشن کنید (یا از میان تماس دکمه‌ی ضبط را بزنید).',
    ],
    folderHint: 'حافظه ← Record ← Call',
    canWatchFolder: true,
    caveat:
        'در بعضی نسخه‌ها ضبط فقط با دکمه‌ی دستی وسط تماس است و ضبط خودکار ندارد.',
  ),
  BrandGuide(
    brand: RecorderBrand.motorola,
    title: 'موتورولا',
    steps: [
      'برنامه‌ی «Phone / تلفن» را باز کنید.',
      'روی سه‌نقطه (⋮) ← «Settings / تنظیمات» بزنید.',
      'گزینه‌ی «Call recording / ضبط تماس» را باز کنید.',
      'یکی از گزینه‌های «Always record / همیشه ضبط شود» را انتخاب کنید.',
    ],
    folderHint: 'معمولاً در پوشه‌ی خصوصی برنامه‌ی تلفن (گوگل) ذخیره می‌شود',
    canWatchFolder: false,
    caveat:
        'موتورولا معمولاً شماره‌گیر گوگل دارد؛ فایل‌های آن برای برنامه‌های دیگر قابل خواندن نیست. '
        'برای موتورولا «ضبط‌کننده‌ی داخلی» (دسترس‌پذیری) راه عملی‌تر است.',
  ),
  BrandGuide(
    brand: RecorderBrand.google,
    title: 'پیکسل / گوگل (Google Phone)',
    steps: [
      'برنامه‌ی «Phone / تلفن» گوگل را باز کنید.',
      'روی سه‌نقطه (⋮) ← «Settings / تنظیمات» ← «Call Recording / ضبط تماس» بزنید.',
      'گزینه‌ی «Always record / همیشه ضبط شود» را برای دسته‌ی دلخواه روشن کنید.',
    ],
    folderHint: 'فقط داخل خود برنامه‌ی Phone گوگل (برای برنامه‌های دیگر دیده نمی‌شود)',
    canWatchFolder: false,
    caveat:
        'ضبط تماس گوگل در بسیاری از کشورها (از جمله ایران) در دسترس نیست و فایل‌هایش هم برای برنامه‌ی دیگر قابل خواندن نیست. '
        'در این گوشی‌ها فقط «ضبط‌کننده‌ی داخلی» (دسترس‌پذیری) ممکن است کار کند.',
  ),
  BrandGuide(
    brand: RecorderBrand.other,
    title: 'سایر گوشی‌ها',
    steps: [
      'در برنامه‌ی «Phone / تلفن» گوشی، تنظیمات را باز کنید و دنبال «ضبط تماس / Call recording» بگردید.',
      'اگر ضبط خودکار دارد روشنش کنید.',
      'اگر چنین گزینه‌ای نیست، از «ضبط‌کننده‌ی داخلی» (دسترس‌پذیری) در همین برنامه استفاده کنید.',
      'یا یک برنامه‌ی ضبط تماس دیگر نصب کنید که فایل را در پوشه‌ای شبیه Call Recordings ذخیره می‌کند؛ برنامه آن را پیدا می‌کند.',
    ],
    folderHint: 'پوشه‌ای با نام شبیه Call / CallRecord / Recordings',
    canWatchFolder: true,
  ),
];

BrandGuide guideFor(RecorderBrand brand) {
  return kBrandGuides.firstWhere(
    (guide) => guide.brand == brand,
    orElse: () => kBrandGuides.last,
  );
}

/// متن اطلاعیه‌ی مسئولیت ضبط تماس که یک‌بار نمایش داده می‌شود.
const String kRecordingConsentText =
    'ضبط مکالمه‌ی تلفنی بدون اطلاع و رضایت طرف مقابل ممکن است طبق قوانین کشور شما جرم باشد.\n\n'
    'مسئولیت اطلاع‌رسانی به افرادی که با آنها تماس می‌گیرید یا از آنها تماس می‌گیرند، '
    'و گرفتن رضایتشان (مثلاً با جمله‌ی «این تماس ضبط می‌شود»)، کاملاً با شماست و '
    'برنامه این کار را به‌جای شما انجام نمی‌دهد.\n\n'
    'ضبط‌ها و متن‌ها فقط در حافظه‌ی همین گوشی ذخیره می‌شوند، مگر خودتان سرویس '
    'تبدیل به متن یا سرور را در تنظیمات وارد کنید؛ در آن صورت صدای ضبط‌شده به همان سرویس فرستاده می‌شود.';
