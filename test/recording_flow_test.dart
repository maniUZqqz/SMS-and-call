import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/features/calls/data/call_settings.dart';
import 'package:sms_and_call/features/calls/data/recording_repository.dart';
import 'package:sms_and_call/features/calls/domain/call_models.dart';
import 'package:sms_and_call/features/calls/services/recording_pipeline.dart';
import 'package:sms_and_call/features/calls/services/recording_scanner.dart';
import 'package:sms_and_call/features/calls/services/transcription.dart';

/// بستر جعلیِ اندروید: فایل‌ها و تماس‌ها از لیست می‌آیند؛ «کپی» یک فایل واقعی می‌نویسد.
class FakePlatform implements CallPlatform {
  final List<RawAudioFile> files = [];
  final List<RawCallLogEntry> calls = [];

  @override
  Future<List<RawAudioFile>> audioSince(DateTime since, {int limit = 500}) async =>
      List.of(files);

  @override
  Future<List<RawCallLogEntry>> callsSince(DateTime since, {int limit = 500}) async =>
      List.of(calls);

  @override
  Future<String?> copyUri(String uri, String destination) async {
    final file = File(destination);
    await file.create(recursive: true);
    await file.writeAsBytes(List<int>.generate(4096, (i) => i % 200));
    return destination;
  }
}

class FakeStt implements SpeechToText {
  FakeStt(this.reply);

  final Object Function(File audio) reply; // String یا TranscriptionException
  int calls = 0;

  @override
  String get name => 'fake-stt';

  @override
  Future<TranscriptionResult> transcribe(File audio, {String? prompt}) async {
    calls++;
    final value = reply(audio);
    if (value is TranscriptionException) throw value;
    return TranscriptionResult(value as String);
  }
}

RawAudioFile _file(
  int id,
  String name,
  String path,
  DateTime modified, {
  int size = 20000,
}) => RawAudioFile(
  id: id,
  uri: 'content://media/external/audio/media/$id',
  displayName: name,
  relativePath: path,
  mime: 'audio/mp4',
  durationMs: 60000,
  sizeBytes: size,
  dateAddedMillis: modified.millisecondsSinceEpoch,
  dateModifiedMillis: modified.millisecondsSinceEpoch,
);

RawCallLogEntry _call(int id, String number, DateTime start, int seconds, {int type = 1, String name = ''}) =>
    RawCallLogEntry(
      id: id,
      number: number,
      name: name,
      startedAtMillis: start.millisecondsSinceEpoch,
      durationSeconds: seconds,
      type: type,
    );

void main() {
  final now = DateTime(2026, 11, 4, 15, 0, 0);
  late Directory dir;
  late RecordingRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rec-flow-');
    repo = RecordingRepository(rootPath: '${dir.path}/store');
  });
  tearDown(() => dir.delete(recursive: true));

  CallRecording sample(String id, {String number = '09123456789', String name = 'علی', TranscriptStatus status = TranscriptStatus.none, String audio = ''}) {
    return CallRecording(
      id: id,
      audioPath: audio,
      sourceKey: 'k$id',
      source: RecordingSource.phoneRecorder,
      recordedAt: now,
      importedAt: now,
      number: number,
      contactName: name,
      transcriptStatus: status,
    );
  }

  group('repository', () {
    test('stores recordings and finds them by name, number and transcript text', () async {
      await repo.upsert(sample('a', name: 'علی رضایی', status: TranscriptStatus.done));
      await repo.upsert(sample('b', number: '09121112233', name: 'مریم'));
      await repo.writeTranscript('a', 'قرار شد فردا ساعت ۱۰ جلسه داشته باشیم');

      expect((await repo.search('رضایی')).map((r) => r.id), ['a']);
      expect((await repo.search('0912111')).map((r) => r.id), ['b']);
      expect((await repo.search('جلسه')).map((r) => r.id), ['a']);
      // ارقام فارسی و عربی و ی/ک عربی یکسان می‌شوند
      expect((await repo.search('ساعت 10')).map((r) => r.id), ['a']);
      expect((await repo.search('علي')).map((r) => r.id), ['a']);
      expect(await repo.search('نامرتبط'), isEmpty);
    });

    test('filters by status', () async {
      await repo.upsert(sample('a', status: TranscriptStatus.done));
      await repo.upsert(sample('b', status: TranscriptStatus.failed));
      await repo.upsert(sample('c', status: TranscriptStatus.queued));

      expect((await repo.search('', filter: RecordingFilter.withText)).map((r) => r.id), ['a']);
      expect((await repo.search('', filter: RecordingFilter.failed)).map((r) => r.id), ['b']);
      expect((await repo.search('', filter: RecordingFilter.pending)).map((r) => r.id), ['c']);
    });

    test('deleting the audio keeps the transcript; deleting both removes the row', () async {
      final audio = File('${dir.path}/a.m4a')..writeAsBytesSync([1, 2, 3]);
      await repo.upsert(sample('a', status: TranscriptStatus.done, audio: audio.path));
      await repo.writeTranscript('a', 'متن');

      await repo.delete('a', deleteTranscript: false);
      expect(audio.existsSync(), isFalse);
      expect((await repo.get('a'))!.hasAudio, isFalse);
      expect(await repo.readTranscript('a'), 'متن');

      await repo.delete('a');
      expect(await repo.get('a'), isNull);
      expect(await repo.readTranscript('a'), '');
    });

    test('a source can only be imported once', () async {
      expect(await repo.addIfNew(sample('a')), isTrue);
      final again = CallRecording(
        id: 'other',
        audioPath: '',
        sourceKey: 'ka',
        source: RecordingSource.phoneRecorder,
        recordedAt: now,
        importedAt: now,
      );
      expect(await repo.addIfNew(again), isFalse);
      expect((await repo.all()), hasLength(1));
    });

    test('a recording can be claimed by only one worker at a time', () async {
      await repo.upsert(sample('a', status: TranscriptStatus.queued, audio: 'x'));
      final first = await repo.claim('a', now: now, lease: const Duration(minutes: 15));
      final second = await repo.claim('a', now: now, lease: const Duration(minutes: 15));
      expect(first, isNotNull);
      expect(second, isNull);
      // مهلت که تمام شود، دوباره قابل ادعا است (کارگر قبلی مرده)
      final later = await repo.claim('a', now: now.add(const Duration(minutes: 20)), lease: const Duration(minutes: 15));
      expect(later, isNotNull);
    });
  });

  group('scanner: phone recorder folder -> app, linked to the call log', () {
    CallSettings settings0() => const CallSettings(consentAcceptedAt: null, autoTranscribe: true, provider: TranscriptionProvider.openAiCompatible);

    RecordingScanner scanner(FakePlatform platform, {CallSettings? settings, String? inApp}) => RecordingScanner(
      platform: platform,
      repository: repo,
      settings: () => settings ?? settings0(),
      inAppDirPath: inApp,
      clock: () => now,
    );

    test('imports a Samsung recording, copies it and links it to the call', () async {
      final platform = FakePlatform();
      final callStart = DateTime(2026, 11, 4, 14, 20);
      platform.files.add(_file(7, 'Call recording Ali_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));
      platform.files.add(_file(8, 'song.mp3', 'Music/', DateTime(2026, 11, 4, 14, 26)));
      platform.calls.add(_call(1, '09123456789', callStart, 300, name: 'Ali Rezaei'));

      final report = await scanner(platform).scan();

      expect(report.imported, 1);
      expect(report.linked, 1);
      final recordings = await repo.all();
      expect(recordings, hasLength(1));
      final r = recordings.single;
      expect(r.number, '09123456789');
      expect(r.contactName, 'Ali Rezaei');
      expect(r.direction, CallDirection.incoming);
      expect(r.callStartedAt, callStart);
      expect(r.callDuration, const Duration(minutes: 5));
      expect(r.linked, isTrue);
      expect(r.brand, 'samsung');
      expect(File(r.audioPath).existsSync(), isTrue);
      expect(r.transcriptStatus, TranscriptStatus.queued);
    });

    test('scanning twice does not duplicate', () async {
      final platform = FakePlatform();
      platform.files.add(_file(7, 'Call recording 09123456789_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));
      await scanner(platform).scan();
      final second = await scanner(platform).scan();

      expect(second.imported, 0);
      expect(await repo.all(), hasLength(1));
    });

    test('a file still being written is deferred, and the scan window does not move past it', () async {
      final platform = FakePlatform();
      final writing = now.subtract(const Duration(seconds: 5));
      platform.files.add(_file(9, 'Call recording 09123456789_261104_145955.m4a', 'Recordings/Call/', writing));

      final report = await scanner(platform).scan();

      expect(report.imported, 0);
      expect(report.deferred, 1);
      expect(report.safeUntil, writing);
    });

    test('a recording whose call log row arrives later is linked on a later scan', () async {
      final platform = FakePlatform();
      platform.files.add(_file(7, 'Call recording 09123456789_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));

      final first = await scanner(platform).scan();
      expect(first.imported, 1);
      expect((await repo.all()).single.linked, isFalse);
      expect((await repo.all()).single.number, '09123456789'); // از نام فایل

      platform.calls.add(_call(1, '09123456789', DateTime(2026, 11, 4, 14, 20), 300));
      final second = await scanner(platform).scan();

      expect(second.relinked, 1);
      expect((await repo.all()).single.linked, isTrue);
    });

    test('tiny files and non-recorder folders are ignored', () async {
      final platform = FakePlatform();
      platform.files.add(_file(1, 'a.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 0), size: 300));
      platform.files.add(_file(2, 'Voice 001.m4a', 'Recordings/Voice Recorder/', DateTime(2026, 11, 4, 14, 0)));

      final report = await scanner(platform).scan();

      expect(report.imported, 0);
    });

    test('folder watching can be switched off', () async {
      final platform = FakePlatform();
      platform.files.add(_file(7, 'Call recording 09123456789_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));

      final report = await scanner(platform, settings: const CallSettings(watchPhoneRecorder: false)).scan();

      expect(report.imported, 0);
    });

    test('without an STT or upload target, new recordings are stored but not queued', () async {
      final platform = FakePlatform();
      platform.files.add(_file(7, 'Call recording 09123456789_261104_142530.m4a', 'Recordings/Call/', DateTime(2026, 11, 4, 14, 25, 30)));

      await scanner(platform, settings: const CallSettings()).scan();

      expect((await repo.all()).single.transcriptStatus, TranscriptStatus.none);
    });

    test('imports in-app (accessibility recorder) files and drops silent ones', () async {
      final platform = FakePlatform();
      final inApp = Directory('${dir.path}/inapp')..createSync();
      final good = File('${inApp.path}/call_1.m4a')..writeAsBytesSync(List.filled(5000, 3));
      File('${inApp.path}/call_1.json').writeAsStringSync(jsonEncode({
        'startedAt': DateTime(2026, 11, 4, 14, 20).millisecondsSinceEpoch,
        'endedAt': DateTime(2026, 11, 4, 14, 25).millisecondsSinceEpoch,
        'direction': 'outgoing',
        'number': '',
        'silent': false,
        'source': 'a11y',
      }));
      final silent = File('${inApp.path}/call_2.m4a')..writeAsBytesSync(List.filled(5000, 0));
      File('${inApp.path}/call_2.json').writeAsStringSync(jsonEncode({
        'startedAt': DateTime(2026, 11, 4, 13).millisecondsSinceEpoch,
        'endedAt': DateTime(2026, 11, 4, 13, 5).millisecondsSinceEpoch,
        'silent': true,
      }));
      // زمان تغییر فایل‌ها را به گذشته ببریم تا «در حال ضبط» حساب نشوند
      final old = DateTime(2026, 11, 4, 14, 30);
      good.setLastModifiedSync(old);
      silent.setLastModifiedSync(old);
      platform.calls.add(_call(1, '09123456789', DateTime(2026, 11, 4, 14, 20), 300, type: 2));

      final report = await scanner(platform, inApp: inApp.path).scan();

      expect(report.imported, 1);
      final r = (await repo.all()).single;
      expect(r.source, RecordingSource.inApp);
      expect(r.number, '09123456789');
      expect(r.direction, CallDirection.outgoing);
      expect(r.linked, isTrue);
      expect(good.existsSync(), isFalse, reason: 'the file moved into the app store');
      expect(silent.existsSync(), isFalse, reason: 'silent recordings are discarded');
    });
  });

  group('pipeline: transcription and upload', () {
    const withStt = CallSettings(
      consentAcceptedAt: null,
      provider: TranscriptionProvider.openAiCompatible,
    );

    Future<CallRecording> queued(String id) async {
      final audio = File('${dir.path}/$id.m4a')..writeAsBytesSync(List.filled(2048, 7));
      final r = sample(id, status: TranscriptStatus.queued, audio: audio.path);
      await repo.upsert(r);
      return r;
    }

    RecordingPipeline pipeline(FakeStt? stt, {CallSettings settings = withStt, RemoteUploader? up, DateTime Function()? clock}) {
      return RecordingPipeline(
        repository: repo,
        settings: () => settings,
        speechToText: () async => stt,
        uploader: () async => up,
        clock: clock ?? () => now,
      );
    }

    test('queued recording is transcribed and saved, searchable afterwards', () async {
      await queued('a');
      final stt = FakeStt((_) => 'سلام، لطفاً فاکتور را بفرستید');

      final processed = await pipeline(stt).processDue();

      expect(processed, 1);
      final r = (await repo.get('a'))!;
      expect(r.transcriptStatus, TranscriptStatus.done);
      expect(r.transcriptProvider, 'fake-stt');
      expect(r.transcribedAt, now);
      expect(r.attempts, 0);
      expect(await repo.readTranscript('a'), 'سلام، لطفاً فاکتور را بفرستید');
      expect((await repo.search('فاکتور')).single.id, 'a');
    });

    test('a temporary error retries later with back-off', () async {
      await queued('a');
      final stt = FakeStt((_) => const TranscriptionException('سرویس در دسترس نیست', retryable: true));

      await pipeline(stt).processDue();
      var r = (await repo.get('a'))!;
      expect(r.transcriptStatus, TranscriptStatus.failed);
      expect(r.permanentFailure, isFalse);
      expect(r.nextAttemptAt, now.add(const Duration(minutes: 2)));
      expect(r.transcriptError, contains('سرویس'));

      // پیش از موعد دست نمی‌زند
      expect(await pipeline(stt).processDue(), 0);
      expect(stt.calls, 1);

      // بعد از موعد، تلاش دوم (با فاصله‌ی بیشتر)
      await pipeline(stt, clock: () => now.add(const Duration(minutes: 3))).processDue();
      r = (await repo.get('a'))!;
      expect(stt.calls, 2);
      expect(r.attempts, 2);
      expect(r.nextAttemptAt, now.add(const Duration(minutes: 3)).add(const Duration(minutes: 10)));
    });

    test('a permanent error (wrong key) is not retried until the user asks', () async {
      await queued('a');
      final stt = FakeStt((_) => const TranscriptionException('کلید API نامعتبر است'));
      final p = pipeline(stt);

      await p.processDue();
      final r = (await repo.get('a'))!;
      expect(r.permanentFailure, isTrue);
      expect(await p.processDue(), 0);

      await p.requeue('a');
      final again = (await repo.get('a'))!;
      expect(again.transcriptStatus, TranscriptStatus.queued);
      expect(again.permanentFailure, isFalse);
    });

    test('gives up after the maximum number of attempts', () async {
      await queued('a');
      final stt = FakeStt((_) => const TranscriptionException('timeout', retryable: true));
      var clock = now;
      final p = RecordingPipeline(
        repository: repo,
        settings: () => withStt,
        speechToText: () async => stt,
        uploader: () async => null,
        clock: () => clock,
        maxAttempts: 3,
      );

      for (var i = 0; i < 6; i++) {
        await p.processDue();
        clock = clock.add(const Duration(hours: 8));
      }

      final r = (await repo.get('a'))!;
      expect(stt.calls, 3);
      expect(r.permanentFailure, isTrue);
      expect(r.transcriptError, contains('دستی'));
    });

    test('a recording that was "running" when the service died is picked up again', () async {
      final audio = File('${dir.path}/z.m4a')..writeAsBytesSync(List.filled(2048, 1));
      await repo.upsert(
        sample('z', status: TranscriptStatus.running, audio: audio.path).copyWith(
          nextAttemptAt: now.subtract(const Duration(minutes: 1)), // مهلت تمام شده
        ),
      );
      final stt = FakeStt((_) => 'متن');

      expect(await pipeline(stt).processDue(), 1);
      expect((await repo.get('z'))!.transcriptStatus, TranscriptStatus.done);
    });

    test('upload to the owner server after transcription; server text is used when no STT is set', () async {
      await queued('a');
      final calls = <String>[];
      final uploader = RemoteUploader(
        url: Uri.parse('https://my.server/up'),
        client: _recordingClient(calls),
      );
      const uploadOnly = CallSettings(uploadEnabled: true, uploadUrl: 'https://my.server/up');

      await pipeline(null, settings: uploadOnly, up: uploader).processDue();

      final r = (await repo.get('a'))!;
      expect(calls, hasLength(1));
      expect(r.uploadedAt, now);
      expect(r.transcriptStatus, TranscriptStatus.done);
      expect(await repo.readTranscript('a'), 'متن از سرور من');
      // دومین دور دوباره آپلود نمی‌کند
      await pipeline(null, settings: uploadOnly, up: uploader).processDue();
      expect(calls, hasLength(1));
    });

    test('nextDueAt reports the earliest retry so the OS alarm can be armed', () async {
      await queued('a');
      final stt = FakeStt((_) => const TranscriptionException('x', retryable: true));
      final p = pipeline(stt);
      await p.processDue();

      expect(await p.nextDueAt(), now.add(const Duration(minutes: 2)));
    });
  });
}

http.Client _recordingClient(List<String> calls) {
  return _UploadClient(calls);
}

// کلاینت جعلیِ ساده که همه‌ی درخواست‌ها را می‌شمارد و متن برمی‌گرداند.
class _UploadClient extends http.BaseClient {
  _UploadClient(this.calls);

  final List<String> calls;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request.url.toString());
    await request.finalize().drain<void>();
    final body = utf8.encode(jsonEncode({'text': 'متن از سرور من'}));
    return http.StreamedResponse(
      Stream.value(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}
