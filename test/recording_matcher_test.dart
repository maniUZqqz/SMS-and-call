import 'package:flutter_test/flutter_test.dart';
import 'package:sms_and_call/features/calls/domain/brand_guide.dart';
import 'package:sms_and_call/features/calls/domain/call_models.dart';
import 'package:sms_and_call/features/calls/domain/recording_matcher.dart';
import 'package:sms_and_call/features/contacts/domain/contact.dart';

void main() {
  group('brand detection', () {
    test('maps manufacturer/brand/model to a brand', () {
      RecorderBrand brand(String m, String b, String model) =>
          detectRecorderBrand(manufacturer: m, brand: b, model: model);

      expect(brand('samsung', 'samsung', 'SM-S918B'), RecorderBrand.samsung);
      expect(brand('Xiaomi', 'Redmi', '23053RN02A'), RecorderBrand.xiaomi);
      expect(brand('Xiaomi', 'POCO', 'M2102J20SG'), RecorderBrand.xiaomi);
      expect(brand('HUAWEI', 'HONOR', 'ANY-LX1'), RecorderBrand.huawei);
      expect(brand('OPPO', 'realme', 'RMX3085'), RecorderBrand.oppo);
      expect(brand('OnePlus', 'OnePlus', 'CPH2449'), RecorderBrand.oppo);
      expect(brand('vivo', 'vivo', 'V2250'), RecorderBrand.vivo);
      expect(brand('motorola', 'motorola', 'moto g54'), RecorderBrand.motorola);
      expect(brand('Google', 'google', 'Pixel 8'), RecorderBrand.google);
      expect(brand('TECNO', 'TECNO', 'KG5'), RecorderBrand.other);
    });

    test('every brand has setup instructions and a folder hint', () {
      for (final brand in RecorderBrand.values) {
        final guide = guideFor(brand);
        expect(guide.steps, isNotEmpty, reason: brand.name);
        expect(guide.folderHint, isNotEmpty, reason: brand.name);
      }
      // گوگل و موتورولا فایل قابل‌خواندن برای برنامه‌ی دیگر نمی‌گذارند
      expect(guideFor(RecorderBrand.google).canWatchFolder, isFalse);
      expect(guideFor(RecorderBrand.samsung).canWatchFolder, isTrue);
    });
  });

  group('recorder folder matching', () {
    FolderMatch? match(String path, [String name = 'a.m4a']) =>
        matchRecordingFolder(relativePath: path, displayName: name);

    test('Samsung', () {
      expect(match('Recordings/Call/')!.brand, RecorderBrand.samsung);
      expect(match('Call/')!.brand, RecorderBrand.samsung);
    });

    test('Xiaomi / MIUI / HyperOS', () {
      expect(match('MIUI/sound_recorder/call_rec/')!.brand, RecorderBrand.xiaomi);
    });

    test('Huawei / Honor', () {
      expect(match('Sounds/CallRecord/')!.brand, RecorderBrand.huawei);
      expect(match('record/callrecord/')!.brand, RecorderBrand.huawei);
    });

    test('Oppo / Realme / OnePlus', () {
      expect(
        match('Music/Recordings/Call Recordings/')!.brand,
        RecorderBrand.oppo,
      );
      expect(match('Recordings/Call Recordings/')!.brand, RecorderBrand.oppo);
    });

    test('Vivo', () {
      expect(match('Record/Call/')!.brand, RecorderBrand.vivo);
    });

    test('third-party recorders are matched by a generic folder name', () {
      final found = match('ACRCalls/');
      expect(found!.brand, RecorderBrand.other);
      expect(found.isConfident, isTrue);
      expect(match('CallRecorder/2026-11/')!.isConfident, isTrue);
    });

    test('ordinary audio is not treated as a call recording', () {
      expect(match('Music/', 'song.mp3'), isNull);
      expect(match('Recordings/Voice Recorder/', 'Voice 001.m4a'), isNull);
      expect(match('Download/', 'Call_me.mp3'), isNull);
      expect(match('Recordings/Call/', 'notes.txt'), isNull);
    });

    test('a call-like file name with a number counts even in an unknown folder', () {
      final found = match('Download/', 'Call_09123456789_20231105.m4a');
      expect(found, isNotNull);
      expect(found!.isConfident, isTrue);
    });
  });

  group('file name parsing', () {
    test('Samsung with a contact name', () {
      final parsed = parseRecordingName('Call recording Ali_231105_142530.m4a');
      expect(parsed.name, 'Ali');
      expect(parsed.number, '');
      expect(parsed.when, DateTime(2023, 11, 5, 14, 25, 30));
    });

    test('Samsung with a number', () {
      final parsed = parseRecordingName(
        'Call recording 09123456789_231105_142530.m4a',
      );
      expect(parsed.number, '09123456789');
      expect(parsed.name, '');
      expect(parsed.when, DateTime(2023, 11, 5, 14, 25, 30));
    });

    test('Xiaomi: name(number)_timestamp', () {
      final parsed = parseRecordingName('علی رضایی(09123456789)_20231105142530.mp3');
      expect(parsed.name, 'علی رضایی');
      expect(parsed.number, '09123456789');
      expect(parsed.when, DateTime(2023, 11, 5, 14, 25, 30));
    });

    test('Huawei: number_timestamp', () {
      final parsed = parseRecordingName('09123456789_20231105142530.amr');
      expect(parsed.number, '09123456789');
      expect(parsed.name, '');
    });

    test('generic with international number and separated timestamp', () {
      final parsed = parseRecordingName('Call_+989123456789_2023-11-05_14-25-30.wav');
      expect(parsed.number, '+989123456789');
      expect(parsed.name, '');
      expect(parsed.when, DateTime(2023, 11, 5, 14, 25, 30));
    });

    test('Persian digits in the number are normalised', () {
      final parsed = parseRecordingName('Call recording ۰۹۱۲۳۴۵۶۷۸۹_231105_142530.m4a');
      expect(parsed.number, '09123456789');
    });

    test('nothing recognisable gives empty fields', () {
      final parsed = parseRecordingName('REC0001.m4a');
      expect(parsed.number, '');
      expect(parsed.when, isNull);
    });
  });

  group('linking a recording to the call log', () {
    final ali = CallLogEntry(
      id: 1,
      number: '09123456789',
      name: 'Ali',
      startedAt: DateTime(2026, 11, 4, 14, 20),
      duration: const Duration(minutes: 5),
      direction: CallDirection.incoming,
    );
    final other = CallLogEntry(
      id: 2,
      number: '09120000000',
      name: '',
      startedAt: DateTime(2026, 11, 4, 14, 0),
      duration: const Duration(minutes: 1),
      direction: CallDirection.outgoing,
    );
    final missed = CallLogEntry(
      id: 3,
      number: '09125555555',
      name: '',
      startedAt: DateTime(2026, 11, 4, 14, 24),
      duration: Duration.zero,
      direction: CallDirection.missed,
    );

    test('the file written right after the call belongs to that call', () {
      final match = findCallForRecording(
        times: [DateTime(2026, 11, 4, 14, 25, 20)],
        calls: [other, ali, missed],
      );
      expect(match!.call.id, 1);
    });

    test('a number in the file name must agree with the call (any format)', () {
      final match = findCallForRecording(
        times: [DateTime(2026, 11, 4, 14, 25, 20)],
        calls: [ali],
        parsedNumber: '+989123456789',
      );
      expect(match!.call.id, 1);

      final wrong = findCallForRecording(
        times: [DateTime(2026, 11, 4, 14, 25, 20)],
        calls: [ali],
        parsedNumber: '09129999999',
      );
      expect(wrong, isNull);
    });

    test('missed calls (zero duration) never have a recording', () {
      final match = findCallForRecording(
        times: [DateTime(2026, 11, 4, 14, 24, 30)],
        calls: [missed],
      );
      expect(match, isNull);
    });

    test('a recording hours away from every call is left unlinked', () {
      final match = findCallForRecording(
        times: [DateTime(2026, 11, 4, 18)],
        calls: [ali, other],
      );
      expect(match, isNull);
    });

    test('the call that ended closest to the file time wins', () {
      final early = CallLogEntry(
        id: 10,
        number: '09121111111',
        name: '',
        startedAt: DateTime(2026, 11, 4, 14, 22),
        duration: const Duration(minutes: 1),
        direction: CallDirection.outgoing,
      );
      final match = findCallForRecording(
        times: [DateTime(2026, 11, 4, 14, 25, 10)],
        calls: [early, ali],
      );
      expect(match!.call.id, 1);
    });

    test('phone keys treat 0912…, +98912… and 0098912… as the same number', () {
      expect(phoneKey('09123456789'), '9123456789');
      expect(phoneKey('+989123456789'), '9123456789');
      expect(phoneKey('00989123456789'), '9123456789');
      expect(phoneKey('۰۹۱۲۳۴۵۶۷۸۹'), '9123456789');
      expect(phoneKey('+14155550123'), '14155550123');
    });
  });
}
