import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sms_and_call/features/calls/services/transcription.dart';

Future<File> _audio({int bytes = 2048, String name = 'rec.m4a'}) async {
  final dir = await Directory.systemTemp.createTemp('stt-');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(List<int>.generate(bytes, (i) => i % 251));
  return file;
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('endpoint resolution', () {
    test('adds /audio/transcriptions to an OpenAI-style base URL', () {
      expect(
        OpenAiCompatibleTranscriber.endpointFor('https://api.openai.com/v1').toString(),
        'https://api.openai.com/v1/audio/transcriptions',
      );
      expect(
        OpenAiCompatibleTranscriber.endpointFor('https://api.openai.com/v1/').toString(),
        'https://api.openai.com/v1/audio/transcriptions',
      );
    });

    test('adds /v1 for a bare local server address', () {
      expect(
        OpenAiCompatibleTranscriber.endpointFor('http://192.168.1.5:8000').toString(),
        'http://192.168.1.5:8000/v1/audio/transcriptions',
      );
    });

    test('accepts a full endpoint unchanged and defaults to https', () {
      expect(
        OpenAiCompatibleTranscriber.endpointFor(
          'https://host.example/openai/v1/audio/transcriptions',
        ).toString(),
        'https://host.example/openai/v1/audio/transcriptions',
      );
      expect(
        OpenAiCompatibleTranscriber.endpointFor('api.groq.com/openai/v1').toString(),
        'https://api.groq.com/openai/v1/audio/transcriptions',
      );
    });

    test('an empty address is rejected', () {
      expect(() => OpenAiCompatibleTranscriber.endpointFor('  '), throwsFormatException);
    });
  });

  group('OpenAI-compatible transcription (mocked HTTP, no network)', () {
    test('sends a multipart request with key, model, language and the audio file', () async {
      final audio = await _audio();
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return _json({'text': '  سلام، حالتان چطور است؟ '});
      });
      final stt = OpenAiCompatibleTranscriber(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        model: 'whisper-large-v3',
        language: 'fa',
        client: client,
      );

      final result = await stt.transcribe(audio, prompt: 'گفتگوی تلفنی');

      expect(result.text, 'سلام، حالتان چطور است؟');
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://api.example.com/v1/audio/transcriptions');
      expect(seen.headers['Authorization'], 'Bearer sk-test');
      expect(seen.headers['content-type'], startsWith('multipart/form-data'));
      final body = latin1.decode(seen.bodyBytes);
      expect(body, contains('name="model"'));
      expect(body, contains('whisper-large-v3'));
      expect(body, contains('name="language"'));
      expect(body, contains('name="response_format"'));
      expect(body, contains('name="prompt"'));
      expect(body, contains('name="file"; filename="rec.m4a"'));
      expect(body.toLowerCase(), contains('content-type: audio/mp4'));
    });

    test('omits the Authorization header when no key is configured (local servers)', () async {
      final audio = await _audio();
      late http.Request seen;
      final stt = OpenAiCompatibleTranscriber(
        baseUrl: 'http://localhost:8000',
        apiKey: '',
        language: '',
        client: MockClient((request) async {
          seen = request;
          return _json({'text': 'ok'});
        }),
      );

      await stt.transcribe(audio);

      expect(seen.headers.containsKey('Authorization'), isFalse);
      expect(latin1.decode(seen.bodyBytes), isNot(contains('name="language"')));
    });

    test('accepts a plain-text reply from simple servers', () async {
      final audio = await _audio();
      final stt = OpenAiCompatibleTranscriber(
        baseUrl: 'http://localhost:8000',
        apiKey: '',
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode('متن ساده'), 200),
        ),
      );
      expect((await stt.transcribe(audio)).text, 'متن ساده');
    });

    test('rejects an HTML error page that came back with 200', () async {
      final audio = await _audio();
      final stt = OpenAiCompatibleTranscriber(
        baseUrl: 'http://localhost:8000',
        apiKey: '',
        client: MockClient((_) async => http.Response('<html>proxy</html>', 200)),
      );
      expect(stt.transcribe(audio), throwsA(isA<TranscriptionException>()));
    });

    Future<TranscriptionException> failWith(int status, [Object? body]) async {
      final audio = await _audio();
      final stt = OpenAiCompatibleTranscriber(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        client: MockClient(
          (_) async => body == null ? http.Response('', status) : _json(body, status),
        ),
      );
      try {
        await stt.transcribe(audio);
      } on TranscriptionException catch (e) {
        return e;
      }
      fail('expected a TranscriptionException');
    }

    test('wrong key (401) is permanent and says so', () async {
      final e = await failWith(401, {
        'error': {'message': 'Incorrect API key provided'},
      });
      expect(e.retryable, isFalse);
      expect(e.message, contains('کلید API'));
      expect(e.message, contains('Incorrect API key'));
    });

    test('wrong address/model (404) is permanent', () async {
      final e = await failWith(404);
      expect(e.retryable, isFalse);
      expect(e.message, contains('۴۰۴'));
    });

    test('rate limiting (429) and server errors (5xx) are retryable', () async {
      expect((await failWith(429)).retryable, isTrue);
      expect((await failWith(500)).retryable, isTrue);
      expect((await failWith(503)).retryable, isTrue);
    });

    test('a 413 from the server is permanent', () async {
      expect((await failWith(413)).retryable, isFalse);
    });

    test('a network failure is retryable', () async {
      final audio = await _audio();
      final stt = OpenAiCompatibleTranscriber(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        client: MockClient((_) async => throw const SocketException('unreachable')),
      );
      try {
        await stt.transcribe(audio);
        fail('should throw');
      } on TranscriptionException catch (e) {
        expect(e.retryable, isTrue);
      }
    });

    test('a hung server times out and is retryable', () async {
      final audio = await _audio();
      final stt = OpenAiCompatibleTranscriber(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        timeout: const Duration(milliseconds: 30),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return _json({'text': 'late'});
        }),
      );
      try {
        await stt.transcribe(audio);
        fail('should time out');
      } on TranscriptionException catch (e) {
        expect(e.retryable, isTrue);
      }
    });

    test('files over the size limit are refused without calling the server', () async {
      final audio = await _audio(bytes: 5000);
      var called = false;
      final stt = OpenAiCompatibleTranscriber(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        maxBytes: 1000,
        client: MockClient((_) async {
          called = true;
          return _json({'text': 'x'});
        }),
      );
      await expectLater(stt.transcribe(audio), throwsA(isA<TranscriptionException>()));
      expect(called, isFalse);
    });

    test('content types follow the file extension', () {
      expect(mediaTypeForAudio('a.mp3').mimeType, 'audio/mpeg');
      expect(mediaTypeForAudio('a.m4a').mimeType, 'audio/mp4');
      expect(mediaTypeForAudio('a.amr').mimeType, 'audio/amr');
      expect(mediaTypeForAudio('a.wav').mimeType, 'audio/wav');
      expect(mediaTypeForAudio('a.ogg').mimeType, 'audio/ogg');
    });
  });

  group('upload to the owner\'s own server', () {
    test('sends metadata, token and audio; returns text if the server transcribed', () async {
      final audio = await _audio();
      late http.Request seen;
      final uploader = RemoteUploader(
        url: Uri.parse('https://my.server/api/calls'),
        token: 'secret-token',
        client: MockClient((request) async {
          seen = request;
          return _json({'text': 'متن از سرور'});
        }),
      );

      final result = await uploader.upload(
        metadata: {'number': '09123456789', 'direction': 'incoming'},
        audio: audio,
      );

      expect(result.transcript, 'متن از سرور');
      expect(seen.headers['Authorization'], 'Bearer secret-token');
      final body = latin1.decode(seen.bodyBytes);
      expect(body, contains('name="number"'));
      expect(body, contains('09123456789'));
      expect(body, contains('name="metadata"'));
      expect(body, contains('name="audio"; filename="rec.m4a"'));
    });

    test('a metadata-only upload carries no audio part', () async {
      late http.Request seen;
      final uploader = RemoteUploader(
        url: Uri.parse('https://my.server/api/calls'),
        client: MockClient((request) async {
          seen = request;
          return http.Response('ok', 200);
        }),
      );

      final result = await uploader.upload(
        metadata: {'number': '1'},
        transcript: 'hello',
      );

      expect(result.transcript, isNull);
      final body = latin1.decode(seen.bodyBytes);
      expect(body, contains('name="transcript"'));
      expect(body, isNot(contains('name="audio"')));
    });

    test('server errors are classified', () async {
      final uploader = RemoteUploader(
        url: Uri.parse('https://my.server/api/calls'),
        client: MockClient((_) async => http.Response('', 502)),
      );
      try {
        await uploader.upload(metadata: const {});
        fail('should throw');
      } on TranscriptionException catch (e) {
        expect(e.retryable, isTrue);
      }
    });
  });
}
