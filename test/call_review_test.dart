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

class _CountingClient extends http.BaseClient {
  _CountingClient(this.statuses);

  final List<int> statuses;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    await request.finalize().drain<void>();
    final status = statuses.isEmpty ? 200 : statuses.removeAt(0);
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), status);
  }
}

class _Stt implements SpeechToText {
  int calls = 0;

  @override
  String get name => 'stt';

  @override
  Future<TranscriptionResult> transcribe(File audio, {String? prompt}) async {
    calls++;
    return const TranscriptionResult('متن آزمایشی');
  }
}

class _FailingCopyPlatform implements CallPlatform {
  _FailingCopyPlatform(this.file);

  final RawAudioFile file;

  @override
  Future<List<RawAudioFile>> audioSince(DateTime since, {int limit = 500}) async => [file];

  @override
  Future<List<RawCallLogEntry>> callsSince(DateTime since, {int limit = 500}) async => const [];

  @override
  Future<String?> copyUri(String uri, String destination) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 4, 12, 0);

  group('transcription pipeline', () {
    late Directory dir;
    late RecordingRepository repo;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('pipe-');
      repo = RecordingRepository(rootPath: '${dir.path}/store');
    });
    tearDown(() => dir.delete(recursive: true));

    Future<void> addQueued() async {
      final audio = File('${dir.path}/a.m4a')..writeAsBytesSync(List.filled(2048, 5));
      await repo.upsert(
        CallRecording(
          id: 'a',
          audioPath: audio.path,
          sourceKey: 'k',
          source: RecordingSource.phoneRecorder,
          recordedAt: now,
          importedAt: now,
          transcriptStatus: TranscriptStatus.queued,
        ),
      );
    }

    test('an upload URL that is not valid never keeps the queue spinning', () async {
      const settings = CallSettings(uploadEnabled: true, uploadUrl: 'not a url');
      expect(settings.uploadConfigured, isFalse);
      expect(settings.hasAnyOutput, isFalse);

      await addQueued();
      await repo.update('a', (r) => r.copyWith(transcriptStatus: TranscriptStatus.done));
      final pipeline = RecordingPipeline(
        repository: repo,
        settings: () => settings,
        speechToText: () async => null,
        uploader: () async => null,
        clock: () => now,
      );

      expect(await pipeline.processDue(), 0);
      expect(await pipeline.nextDueAt(), isNull);
    });

    test('when only the upload failed, the retry does not pay for a second transcription', () async {
      await addQueued();
      final stt = _Stt();
      final client = _CountingClient([503, 200]);
      const settings = CallSettings(
        provider: TranscriptionProvider.openAiCompatible,
        uploadEnabled: true,
        uploadUrl: 'https://my.server/up',
      );
      var clock = now;
      final pipeline = RecordingPipeline(
        repository: repo,
        settings: () => settings,
        speechToText: () async => stt,
        uploader: () async => RemoteUploader(url: Uri.parse('https://my.server/up'), client: client),
        clock: () => clock,
      );

      await pipeline.processDue();
      var r = (await repo.get('a'))!;
      expect(stt.calls, 1);
      expect(client.calls, 1);
      expect(r.transcriptStatus, TranscriptStatus.failed);
      expect(await repo.readTranscript('a'), 'متن آزمایشی');
      expect(r.uploadedAt, isNull);

      clock = now.add(const Duration(minutes: 5));
      await pipeline.processDue();
      r = (await repo.get('a'))!;
      expect(stt.calls, 1, reason: 'the transcript already existed');
      expect(client.calls, 2);
      expect(r.uploadedAt, isNotNull);
      expect(r.transcriptStatus, TranscriptStatus.done);
    });

    test('the user can force a fresh transcription', () async {
      await addQueued();
      final stt = _Stt();
      const settings = CallSettings(provider: TranscriptionProvider.openAiCompatible);
      final pipeline = RecordingPipeline(
        repository: repo,
        settings: () => settings,
        speechToText: () async => stt,
        uploader: () async => null,
        clock: () => now,
      );
      await pipeline.processDue();
      expect(stt.calls, 1);

      await pipeline.requeue('a', retranscribe: true);
      expect(await repo.readTranscript('a'), '');
      await pipeline.processDue();
      expect(stt.calls, 2);
    });
  });

  test('a file that cannot be copied holds the scan watermark back so it is retried', () async {
    final dir = await Directory.systemTemp.createTemp('scan-');
    addTearDown(() => dir.delete(recursive: true));
    final modified = DateTime(2026, 11, 4, 11, 0);
    final file = RawAudioFile(
      id: 5,
      uri: 'content://media/5',
      displayName: 'Call recording 09123456789_261104_110000.m4a',
      relativePath: 'Recordings/Call/',
      mime: 'audio/mp4',
      durationMs: 60000,
      sizeBytes: 20000,
      dateAddedMillis: modified.millisecondsSinceEpoch,
      dateModifiedMillis: modified.millisecondsSinceEpoch,
    );
    final scanner = RecordingScanner(
      platform: _FailingCopyPlatform(file),
      repository: RecordingRepository(rootPath: '${dir.path}/store'),
      settings: () => const CallSettings(),
      clock: () => now,
    );

    final report = await scanner.scan();

    expect(report.imported, 0);
    expect(report.deferred, 1);
    expect(report.safeUntil, modified);
  });
}
