import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// خطای تبدیل صدا به متن؛ پیام فارسی و قابل نمایش به کاربر است.
class TranscriptionException implements Exception {
  const TranscriptionException(
    this.message, {
    this.retryable = false,
    this.statusCode,
  });

  final String message;

  /// خطاهای موقت (شبکه، ۵۰۰، ۴۲۹) با فاصله دوباره امتحان می‌شوند؛ بقیه (کلید اشتباه،
  /// فایل بزرگ) تا اصلاح توسط کاربر نه.
  final bool retryable;
  final int? statusCode;

  @override
  String toString() => message;
}

class TranscriptionResult {
  const TranscriptionResult(this.text, {this.language});

  final String text;
  final String? language;
}

/// هر سرویس تبدیل گفتار به متن این رابط را پیاده می‌کند (قابل جایگزینی).
abstract interface class SpeechToText {
  String get name;

  Future<TranscriptionResult> transcribe(File audio, {String? prompt});
}

/// نوع محتوا از روی پسوند فایل.
MediaType mediaTypeForAudio(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.mp3')) return MediaType('audio', 'mpeg');
  if (lower.endsWith('.wav')) return MediaType('audio', 'wav');
  if (lower.endsWith('.ogg') || lower.endsWith('.opus')) {
    return MediaType('audio', 'ogg');
  }
  if (lower.endsWith('.flac')) return MediaType('audio', 'flac');
  if (lower.endsWith('.amr')) return MediaType('audio', 'amr');
  if (lower.endsWith('.3gp') || lower.endsWith('.3ga')) {
    return MediaType('audio', '3gpp');
  }
  if (lower.endsWith('.aac')) return MediaType('audio', 'aac');
  if (lower.endsWith('.webm')) return MediaType('audio', 'webm');
  return MediaType('audio', 'mp4'); // m4a و mp4
}

/// سرویس سازگار با OpenAI (`POST {base}/audio/transcriptions`): خودِ OpenAI، Groq،
/// faster-whisper-server، LocalAI، whisper.cpp server و …
class OpenAiCompatibleTranscriber implements SpeechToText {
  OpenAiCompatibleTranscriber({
    required String baseUrl,
    required this.apiKey,
    this.model = 'whisper-1',
    this.language = 'fa',
    http.Client? client,
    this.timeout = const Duration(minutes: 5),
    this.maxBytes = 24 * 1024 * 1024,
  }) : endpoint = endpointFor(baseUrl),
       _client = client ?? http.Client();

  final Uri endpoint;
  final String apiKey;
  final String model;

  /// کد زبان ISO-639-1 (مثلاً `fa`)؛ خالی یعنی تشخیص خودکار.
  final String language;
  final Duration timeout;

  /// سقف اندازه‌ی فایل (OpenAI: ۲۵ مگابایت).
  final int maxBytes;
  final http.Client _client;

  @override
  String get name => 'OpenAI-compatible (${endpoint.host})';

  /// آدرس پایه (مثلاً `https://api.openai.com/v1` یا `http://192.168.1.5:8000`) را به
  /// آدرس کامل `…/audio/transcriptions` تبدیل می‌کند.
  static Uri endpointFor(String baseUrl) {
    var text = baseUrl.trim();
    if (text.isEmpty) throw const FormatException('آدرس سرویس خالی است.');
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.parse(text);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 &&
        segments[segments.length - 2] == 'audio' &&
        segments.last == 'transcriptions') {
      return uri;
    }
    final hasVersion = segments.any((s) => RegExp(r'^v\d+$').hasMatch(s));
    final path = <String>[
      ...segments,
      if (!hasVersion) 'v1',
      'audio',
      'transcriptions',
    ];
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: path,
    );
  }

  @override
  Future<TranscriptionResult> transcribe(File audio, {String? prompt}) async {
    final length = await audio.length();
    if (length == 0) {
      throw const TranscriptionException('فایل صوتی خالی است.');
    }
    if (length > maxBytes) {
      throw TranscriptionException(
        'فایل صوتی از ${(maxBytes / (1024 * 1024)).floor()} مگابایت بزرگ‌تر است و سرویس نمی‌پذیرد.',
      );
    }

    final request = http.MultipartRequest('POST', endpoint)
      ..fields['model'] = model
      ..fields['response_format'] = 'json'
      ..fields['temperature'] = '0';
    if (language.trim().isNotEmpty) request.fields['language'] = language.trim();
    if (prompt != null && prompt.trim().isNotEmpty) {
      request.fields['prompt'] = prompt.trim();
    }
    if (apiKey.trim().isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        audio.path,
        filename: audio.uri.pathSegments.last,
        contentType: mediaTypeForAudio(audio.path),
      ),
    );

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } on TimeoutException {
      throw const TranscriptionException(
        'سرویس تبدیل به متن پاسخ نداد (زمان انتظار تمام شد).',
        retryable: true,
      );
    } on SocketException catch (e) {
      throw TranscriptionException(
        'اتصال به سرویس تبدیل به متن برقرار نشد (${e.message}).',
        retryable: true,
      );
    } on http.ClientException catch (e) {
      throw TranscriptionException(
        'خطای شبکه در ارتباط با سرویس: ${e.message}',
        retryable: true,
      );
    } on HandshakeException {
      throw const TranscriptionException(
        'گواهی امنیتی (SSL) سرویس معتبر نیست.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseBody(response);
    }
    throw _errorFor(response);
  }

  TranscriptionResult _parseBody(http.Response response) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final text = decoded['text'];
        if (text is String) {
          return TranscriptionResult(
            text.trim(),
            language: decoded['language']?.toString(),
          );
        }
      }
    } on FormatException {
      // بعضی سرورها متن ساده برمی‌گردانند
      if (body.isNotEmpty && !body.startsWith('<')) {
        return TranscriptionResult(body);
      }
    }
    throw const TranscriptionException(
      'پاسخ سرویس قابل فهم نبود (فیلد text پیدا نشد). آدرس و مدل را بررسی کنید.',
    );
  }

  TranscriptionException _errorFor(http.Response response) {
    final code = response.statusCode;
    var detail = '';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (decoded is Map) {
        final error = decoded['error'];
        detail = error is Map
            ? (error['message'] ?? '').toString()
            : (error ?? decoded['message'] ?? decoded['detail'] ?? '').toString();
      }
    } catch (_) {}
    if (detail.length > 160) detail = '${detail.substring(0, 160)}…';
    final suffix = detail.isEmpty ? '' : ' ($detail)';

    if (code == 401 || code == 403) {
      return TranscriptionException(
        'کلید API نامعتبر است یا دسترسی ندارد$suffix',
        statusCode: code,
      );
    }
    if (code == 404) {
      return TranscriptionException(
        'آدرس یا نام مدل اشتباه است (۴۰۴)$suffix',
        statusCode: code,
      );
    }
    if (code == 413) {
      return TranscriptionException(
        'فایل برای سرویس بیش از حد بزرگ است$suffix',
        statusCode: code,
      );
    }
    if (code == 400 || code == 415 || code == 422) {
      return TranscriptionException(
        'سرویس این فایل یا تنظیمات را نپذیرفت ($code)$suffix',
        statusCode: code,
      );
    }
    if (code == 408 || code == 429 || code >= 500) {
      return TranscriptionException(
        code == 429
            ? 'سقف درخواست سرویس پر شده؛ کمی بعد دوباره تلاش می‌شود$suffix'
            : 'سرویس موقتاً در دسترس نیست ($code)$suffix',
        retryable: true,
        statusCode: code,
      );
    }
    return TranscriptionException(
      'پاسخ غیرمنتظره از سرویس ($code)$suffix',
      statusCode: code,
    );
  }

  void close() => _client.close();
}

/// نتیجه‌ی ارسال ضبط به سرور خود کاربر.
class UploadResult {
  const UploadResult({this.transcript});

  /// اگر سرور خودش متن را برگرداند.
  final String? transcript;
}

/// ارسال ضبط (و اطلاعات تماس) به سرور کاربر. سرور می‌تواند در پاسخ `{"text": "..."}`
/// برگرداند تا به‌عنوان متن ضبط ذخیره شود.
class RemoteUploader {
  RemoteUploader({
    required this.url,
    this.token = '',
    http.Client? client,
    this.timeout = const Duration(minutes: 5),
  }) : _client = client ?? http.Client();

  final Uri url;
  final String token;
  final Duration timeout;
  final http.Client _client;

  Future<UploadResult> upload({
    required Map<String, String> metadata,
    File? audio,
    String? transcript,
  }) async {
    final request = http.MultipartRequest('POST', url)
      ..fields['metadata'] = jsonEncode(metadata);
    metadata.forEach((key, value) => request.fields[key] = value);
    if (transcript != null && transcript.isNotEmpty) {
      request.fields['transcript'] = transcript;
    }
    if (token.trim().isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    if (audio != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'audio',
          audio.path,
          filename: audio.uri.pathSegments.last,
          contentType: mediaTypeForAudio(audio.path),
        ),
      );
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } on TimeoutException {
      throw const TranscriptionException(
        'سرور شما پاسخ نداد (زمان انتظار تمام شد).',
        retryable: true,
      );
    } on SocketException catch (e) {
      throw TranscriptionException(
        'اتصال به سرور شما برقرار نشد (${e.message}).',
        retryable: true,
      );
    } on http.ClientException catch (e) {
      throw TranscriptionException(
        'خطای شبکه در ارسال به سرور: ${e.message}',
        retryable: true,
      );
    }

    final code = response.statusCode;
    if (code >= 200 && code < 300) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map && decoded['text'] is String) {
          final text = (decoded['text'] as String).trim();
          if (text.isNotEmpty) return UploadResult(transcript: text);
        }
      } catch (_) {}
      return const UploadResult();
    }
    throw TranscriptionException(
      code == 401 || code == 403
          ? 'سرور شما دسترسی را رد کرد ($code). توکن را بررسی کنید.'
          : 'سرور شما خطا برگرداند ($code).',
      retryable: code == 408 || code == 429 || code >= 500,
      statusCode: code,
    );
  }

  void close() => _client.close();
}
