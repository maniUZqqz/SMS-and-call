import 'dart:async';
import 'dart:math';

import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/core/errors/error_classifier.dart';
import 'package:sms_and_call/features/campaigns/domain/scheduled_campaign.dart';
import 'package:sms_and_call/features/contacts/domain/contact.dart';
import 'package:sms_and_call/features/contacts/domain/sms_campaign.dart';
import 'package:sms_and_call/features/settings/domain/send_settings.dart';

typedef SmsSender =
    Future<SmsSendResult> Function({
      required String to,
      required String message,
      required int subId,
    });

typedef CampaignProgress =
    Future<void> Function(
      SmsCampaign campaign,
      CampaignState state, {
      String? currentContact,
      bool? lastSendSucceeded,
      String? note,
    });

enum RunStatus { completed, cancelled, windowEnded, paused, failed }

class RunResult {
  const RunResult(this.status, this.campaign, {this.error, this.resumeAt});

  final RunStatus status;
  final SmsCampaign campaign;
  final String? error;

  /// فقط برای [RunStatus.paused]: زمانی که ارسال باید ادامه پیدا کند.
  final DateTime? resumeAt;
}

enum SendFailureKind {
  /// مشکل از خودِ گیرنده/متن است؛ تکرار فایده ندارد.
  permanent,

  /// آنتن، رادیو، مودم… ؛ با کمی صبر درست می‌شود.
  transient,

  /// سقف ارسال اندروید/اپراتور؛ باید طولانی صبر کرد.
  rateLimited,

  /// گزارش ارسال نرسید؛ ممکن است پیامک رفته باشد، پس برای جلوگیری از تکرار دوباره نمی‌فرستیم.
  uncertain,

  /// کل ارسال بی‌معنی است (مجوز نیست، قابلیت تلفن نیست…).
  fatal,
}

SendFailureKind classifySendFailure(SmsSendResult result) {
  // پیامک چندبخشی که فقط بعضی بخش‌هایش رفته: تکرار کامل، بخش اول را دوبار می‌فرستد
  if (result.partsOk > 0 && result.partsOk < result.parts) {
    return SendFailureKind.uncertain;
  }
  switch (result.code) {
    case -103: // مجوز
    case -104: // بدون تلفن
    case -106: // افزونه بومی
    case 32: // برنامه‌ی پیش‌فرض پیامک
      return SendFailureKind.fatal;
    case -100:
      return SendFailureKind.uncertain;
    case 5:
      return SendFailureKind.rateLimited;
  }
  if (ErrorClassifier.smsResult(result).permanent) {
    return SendFailureKind.permanent;
  }
  return SendFailureKind.transient;
}

/// اجرای یک کمپین (تکی یا گروهی) بدون وابستگی به سرویس پس‌زمینه یا ساعت واقعی؛ همه‌ی
/// وابستگی‌ها تزریق می‌شوند تا بشود با ساعت جعلی در تست، منطق زمان‌بندی را بررسی کرد.
class CampaignRunner {
  CampaignRunner({
    required this.send,
    required this.onProgress,
    required this.loadOptOutKeys,
    required this.settings,
    required this.ledger,
    required this.resolveSubId,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    Random? random,
    this.pauseThreshold = const Duration(minutes: 10),
    this.retryBackoff = const [
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ],
    this.rateLimitPause = const Duration(minutes: 15),
  }) : _clock = clock ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? Random();

  final SmsSender send;
  final CampaignProgress onProgress;
  final Future<Set<String>> Function() loadOptOutKeys;
  final SendSettings Function() settings;
  final SendLedger ledger;
  final Future<int> Function() resolveSubId;

  /// انتظارهای کوتاه‌تر از این داخل همین اجرا می‌گذرند؛ طولانی‌تر یعنی «مکث» و
  /// بیدارکردنِ بعدی با آلارم سیستم‌عامل.
  final Duration pauseThreshold;
  final List<Duration> retryBackoff;
  final Duration rateLimitPause;

  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;
  final Random _random;

  bool cancelRequested = false;
  bool stopRequested = false;

  Set<String> _optOut = const {};
  DateTime? _optOutLoadedAt;
  int? _subId;
  DateTime? _subIdAt;
  DateTime? _announcedWaitFor;

  Future<RunResult> run(SmsCampaign initial) async {
    var campaign = initial.resolveInterrupted();
    final seen = <String>{};
    for (var i = 0; i < campaign.nextIndex && i < campaign.totalCount; i++) {
      seen.add(phoneKey(campaign.recipients[i].phone));
    }
    var consecutiveFailures = 0;

    while (campaign.nextIndex < campaign.totalCount) {
      if (stopRequested) {
        return RunResult(RunStatus.paused, campaign, resumeAt: _clock());
      }
      if (cancelRequested) return RunResult(RunStatus.cancelled, campaign);

      var now = _clock();
      var target = _earliestSendTime(campaign, now);
      if (target == null) return RunResult(RunStatus.windowEnded, campaign);

      if (target.isAfter(now)) {
        final wait = target.difference(now);
        if (wait > pauseThreshold) {
          return RunResult(RunStatus.paused, campaign, resumeAt: target);
        }
        if (_announcedWaitFor != target) {
          _announcedWaitFor = target;
          await onProgress(campaign, CampaignState.waiting);
        }
        await _waitUntil(target, campaign.endsAt);
        continue;
      }
      _announcedWaitFor = null;

      final recipient = campaign.recipients[campaign.nextIndex];
      final key = phoneKey(recipient.phone);

      if (!isValidPhoneNumber(recipient.phone)) {
        campaign = _skip(campaign, recipient, 'invalid');
        seen.add(key);
        continue;
      }
      if (seen.contains(key)) {
        campaign = _skip(campaign, recipient, 'duplicate');
        continue;
      }
      if ((await _currentOptOut(now)).contains(key)) {
        campaign = _skip(campaign, recipient, 'optout');
        seen.add(key);
        continue;
      }

      final capWait = ledger.waitBeforeNext(now, settings());
      if (capWait != null) {
        campaign = campaign.copyWith(notBefore: now.add(capWait));
        continue;
      }

      // ثبتِ «در حال ارسال» پیش از ارسال: اگر برنامه همین‌جا بمیرد، بعداً پیامک تکراری نمی‌رود.
      campaign = campaign.copyWith(
        inFlightIndex: campaign.nextIndex,
        attempt: campaign.attempt + 1,
        clearNotBefore: true,
      );
      await onProgress(
        campaign,
        CampaignState.sending,
        currentContact: recipient.name,
      );

      final result = await send(
        to: recipient.phone,
        message: campaign.message,
        subId: await _currentSubId(now),
      );
      now = _clock();

      if (result.ok) {
        consecutiveFailures = 0;
        ledger.record(now);
        seen.add(key);
        campaign = campaign.copyWith(
          nextIndex: campaign.nextIndex + 1,
          sentCount: campaign.sentCount + 1,
          sentRecipientIds: [...campaign.sentRecipientIds, recipient.contactId],
          inFlightIndex: -1,
          attempt: 0,
          notBefore: _nextSendNotBefore(campaign, now),
        );
        await onProgress(
          campaign,
          CampaignState.sending,
          currentContact: recipient.name,
          lastSendSucceeded: true,
        );
        continue;
      }

      final info = ErrorClassifier.smsResult(result);
      final kind = classifySendFailure(result);
      switch (kind) {
        case SendFailureKind.fatal:
          campaign = campaign.copyWith(inFlightIndex: -1, attempt: 0);
          return RunResult(RunStatus.failed, campaign, error: info.title);

        case SendFailureKind.permanent:
        case SendFailureKind.uncertain:
          consecutiveFailures = 0;
          seen.add(key);
          campaign = _fail(
            campaign,
            recipient,
            kind == SendFailureKind.uncertain
                ? '${info.title} (نتیجه نامعلوم؛ برای جلوگیری از تکرار دوباره ارسال نشد)'
                : info.title,
            now,
          );

        case SendFailureKind.rateLimited:
          // این گیرنده تقصیری ندارد؛ بعد از مکثِ طولانی دوباره امتحان می‌شود.
          campaign = campaign.copyWith(
            inFlightIndex: -1,
            attempt: max(0, campaign.attempt - 1),
            notBefore: now.add(rateLimitPause),
          );

        case SendFailureKind.transient:
          consecutiveFailures++;
          if (campaign.attempt > settings().retryAttempts) {
            seen.add(key);
            campaign = _fail(campaign, recipient, info.title, now);
          } else {
            final index = min(campaign.attempt - 1, retryBackoff.length - 1);
            var wait = retryBackoff[max(0, index)];
            campaign = campaign.copyWith(
              inFlightIndex: -1,
              notBefore: now.add(wait),
            );
            // رد شدنِ مکرر یعنی مشکل از آنتن/سیم‌کارت است نه یک گیرنده.
            if (consecutiveFailures >= settings().pauseAfterFailures) {
              wait = Duration(minutes: settings().pauseMinutes);
              campaign = campaign.copyWith(notBefore: now.add(wait));
              consecutiveFailures = 0;
            }
          }
      }
      _subId = null; // شاید سیم عوض شده باشد
      await onProgress(
        campaign,
        CampaignState.sending,
        currentContact: recipient.name,
        lastSendSucceeded: false,
        note: info.title,
      );
    }

    return RunResult(RunStatus.completed, campaign);
  }

  /// نخستین لحظه‌ای که ارسال مجاز است (بازه‌ی روزانه + «نه زودتر از»)؛ null = بازه تمام شد.
  DateTime? _earliestSendTime(SmsCampaign campaign, DateTime now) {
    DateTime? windowed(DateTime from) => nextAllowedCampaignTime(
      now: from,
      startsAt: campaign.startsAt,
      endsAt: campaign.endsAt,
      dailyStartMinute: campaign.dailyStartMinute,
      dailyEndMinute: campaign.dailyEndMinute,
    );

    final notBefore = campaign.notBefore;
    final from = notBefore != null && notBefore.isAfter(now) ? notBefore : now;
    return windowed(from);
  }

  /// بعد از هر ارسال موفق: فاصله‌ی انتخابی کمپین (حداقل = حداقل فاصله‌ی تنظیمات) + کمی تصادف.
  DateTime? _nextSendNotBefore(SmsCampaign campaign, DateTime now) {
    if (campaign.nextIndex + 1 >= campaign.totalCount) return null;
    final config = settings();
    final base = max(campaign.intervalSeconds, config.minDelaySeconds);
    final jitter = config.jitterPercent <= 0
        ? 0.0
        : _random.nextDouble() * config.jitterPercent / 100.0;
    final millis = (base * 1000 * (1 + jitter)).round();
    return now.add(Duration(milliseconds: millis));
  }

  SmsCampaign _skip(SmsCampaign campaign, CampaignRecipient who, String why) {
    return campaign.copyWith(
      nextIndex: campaign.nextIndex + 1,
      skipped: {...campaign.skipped, who.contactId: why},
      inFlightIndex: -1,
      attempt: 0,
    );
  }

  SmsCampaign _fail(
    SmsCampaign campaign,
    CampaignRecipient who,
    String note,
    DateTime now,
  ) {
    return campaign.copyWith(
      nextIndex: campaign.nextIndex + 1,
      failedCount: campaign.failedCount + 1,
      failedRecipientIds: [...campaign.failedRecipientIds, who.contactId],
      failureNotes: {...campaign.failureNotes, who.contactId: note},
      inFlightIndex: -1,
      attempt: 0,
      notBefore: _nextSendNotBefore(campaign, now),
    );
  }

  Future<Set<String>> _currentOptOut(DateTime now) async {
    final loadedAt = _optOutLoadedAt;
    if (loadedAt == null ||
        now.difference(loadedAt) > const Duration(seconds: 5)) {
      _optOut = await loadOptOutKeys();
      _optOutLoadedAt = now;
    }
    return _optOut;
  }

  Future<int> _currentSubId(DateTime now) async {
    final cached = _subId;
    final at = _subIdAt;
    if (cached != null &&
        at != null &&
        now.difference(at) < const Duration(minutes: 10)) {
      return cached;
    }
    final value = await resolveSubId();
    _subId = value;
    _subIdAt = now;
    return value;
  }

  Future<void> _waitUntil(DateTime target, DateTime deadline) async {
    while (!cancelRequested && !stopRequested) {
      final now = _clock();
      if (!now.isBefore(target) || !now.isBefore(deadline)) return;
      final remaining = target.difference(now);
      await _sleep(
        remaining > const Duration(seconds: 1)
            ? const Duration(seconds: 1)
            : remaining,
      );
    }
  }
}
