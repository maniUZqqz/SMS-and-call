import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sms_and_call/core/storage/app_storage.dart';
import 'package:sms_and_call/core/storage/file_mutex.dart';
import 'package:sms_and_call/features/contacts/data/contact_importer.dart';
import 'package:sms_and_call/features/optout/optout.dart';
import 'package:sms_and_call/features/settings/domain/send_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('opt-out markers', () {
    test('Persian and English spellings of "cancel / unsubscribe"', () {
      for (final yes in [
        'لغو',
        'لغو شده',
        'لغو‌شده', // با نیم‌فاصله
        'انصراف',
        'ارسال نشود',
        'STOP',
        'Unsubscribed',
        'opt-out',
        'DNC',
      ]) {
        expect(looksLikeOptOutMarker(yes), isTrue, reason: yes);
      }
      for (final no in ['', 'فعال', 'مشتری ویژه', 'active', 'ok', 'منتظر']) {
        expect(looksLikeOptOutMarker(no), isFalse, reason: no);
      }
    });
  });

  group('opt-out list storage', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('optout-');
      AppDir.setPathForTests(dir.path);
    });
    tearDown(() async {
      AppDir.setPathForTests(null);
      await dir.delete(recursive: true);
    });

    test('numbers are stored once whatever their format', () async {
      expect(await OptOutStorage.add(OptOutEntry.create(phone: '09123456789', name: 'علی')), isTrue);
      expect(await OptOutStorage.add(OptOutEntry.create(phone: '+989123456789')), isFalse);
      expect(await OptOutStorage.add(OptOutEntry.create(phone: '۰۹۱۲۰۰۰۰۰۰۱')), isTrue);

      final keys = await OptOutStorage.loadKeys();
      expect(keys, {'9123456789', '9120000001'});
    });

    test('removing works across formats and survives reload', () async {
      await OptOutStorage.add(OptOutEntry.create(phone: '09123456789'));
      await OptOutStorage.remove('+989123456789');
      expect(await OptOutStorage.load(), isEmpty);
    });

    test('bulk add reports how many were new', () async {
      final added = await OptOutStorage.addAll([
        OptOutEntry.create(phone: '09120000001'),
        OptOutEntry.create(phone: '09120000002'),
        OptOutEntry.create(phone: '09120000001'),
      ]);
      expect(added, 2);
    });
  });

  group('import: opt-out status column and duplicates', () {
    Future<ContactImportResult> parseCsv(String csv) async {
      final dir = await Directory.systemTemp.createTemp('imp-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/c.csv')..writeAsBytesSync(utf8.encode(csv));
      return ContactImporter.parse(path: file.path, fileName: 'c.csv');
    }

    test('a «وضعیت» column with «لغو» marks the contact as opted out', () async {
      final result = await parseCsv(
        'نام,شماره موبایل,وضعیت\n'
        'علی,09120000001,فعال\n'
        'مریم,09120000002,لغو\n'
        'رضا,09120000003,لغو شده\n',
      );
      expect(result.contacts.map((c) => c.optedOut), [false, true, true]);
    });

    test('a «لغو» flag column treats any positive value as opt-out', () async {
      final result = await parseCsv(
        'نام,شماره موبایل,لغو\n'
        'علی,09120000001,\n'
        'مریم,09120000002,1\n'
        'رضا,09120000003,0\n'
        'نگار,09120000004,بله\n',
      );
      expect(result.contacts.map((c) => c.optedOut), [false, true, false, true]);
    });

    test('files without a status column import normally', () async {
      final result = await parseCsv('نام,شماره موبایل\nعلی,09120000001\n');
      expect(result.contacts.single.optedOut, isFalse);
    });

    test('duplicates against existing contacts and inside the file are dropped', () {
      const rows = [
        ImportedContactData(name: 'الف', phone: '09120000001', note: ''),
        ImportedContactData(name: 'ب', phone: '+989120000002', note: ''),
        ImportedContactData(name: 'ب۲', phone: '09120000002', note: ''),
        ImportedContactData(name: 'ج', phone: '09120000003', note: ''),
      ];
      final result = dedupeImportedContacts(['0912 000 0001'.replaceAll(' ', '')], rows);

      expect(result.unique.map((c) => c.name), ['ب', 'ج']);
      expect(result.duplicates, 2);
    });
  });

  group('send settings and the hourly ledger', () {
    test('values are clamped to safe limits', () {
      final s = const SendSettings(
        minDelaySeconds: 0,
        jitterPercent: 500,
        retryAttempts: 99,
        pauseAfterFailures: 0,
      ).normalized();
      expect(s.minDelaySeconds, SendSettings.hardMinDelaySeconds);
      expect(s.jitterPercent, 100);
      expect(s.retryAttempts, 10);
      expect(s.pauseAfterFailures, 1);
    });

    test('JSON round trip keeps the owner choices', () {
      const original = SendSettings(minDelaySeconds: 25, maxPerHour: 60, maxPerDay: 400);
      final restored = SendSettings.fromJson(original.toJson());
      expect(restored.minDelaySeconds, 25);
      expect(restored.maxPerHour, 60);
      expect(restored.maxPerDay, 400);
    });

    test('ledger: no wait below the cap, exact wait at the cap, window slides', () {
      final t0 = DateTime(2026, 11, 4, 10);
      const settings = SendSettings(maxPerHour: 3);
      final ledger = SendLedger();
      for (var i = 0; i < 2; i++) {
        ledger.record(t0.add(Duration(minutes: i * 10)));
      }
      expect(ledger.waitBeforeNext(t0.add(const Duration(minutes: 20)), settings), isNull);

      ledger.record(t0.add(const Duration(minutes: 20)));
      expect(
        ledger.waitBeforeNext(t0.add(const Duration(minutes: 30)), settings),
        const Duration(minutes: 30), // تا خروج اولین ارسال (ساعت ۱۰:۰۰) از پنجره‌ی یک ساعته
      );
      expect(ledger.waitBeforeNext(t0.add(const Duration(minutes: 61)), settings), isNull);
    });

    test('ledger: zero means unlimited, and the daily cap works too', () {
      final t0 = DateTime(2026, 11, 4, 10);
      final ledger = SendLedger([for (var i = 0; i < 5; i++) t0.add(Duration(minutes: i))]);
      expect(ledger.waitBeforeNext(t0, const SendSettings(maxPerHour: 0, maxPerDay: 0)), isNull);
      expect(
        ledger.waitBeforeNext(t0.add(const Duration(minutes: 10)), const SendSettings(maxPerHour: 0, maxPerDay: 5)),
        const Duration(hours: 23, minutes: 50),
      );
    });
  });

  group('FileMutex', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('mutex-'));
    tearDown(() => dir.delete(recursive: true));

    test('concurrent read-modify-write cycles never lose an update', () async {
      final counter = File('${dir.path}/counter.txt')..writeAsStringSync('0');
      final lockPath = '${dir.path}/counter.lock';

      Future<void> bump() => FileMutex(lockPath).synchronized(() async {
        final value = int.parse(await counter.readAsString());
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await counter.writeAsString('${value + 1}');
      });

      await Future.wait([for (var i = 0; i < 25; i++) bump()]);

      expect(counter.readAsStringSync(), '25');
      expect(File(lockPath).existsSync(), isFalse, reason: 'lock file is released');
    });

    test('a stale lock left by a dead process is broken', () async {
      final lockPath = '${dir.path}/x.lock';
      final stale = File(lockPath)..writeAsStringSync('');
      stale.setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 5)));

      var ran = false;
      await FileMutex(lockPath, staleAfter: const Duration(seconds: 5)).synchronized(() async {
        ran = true;
      });

      expect(ran, isTrue);
    });
  });
}
