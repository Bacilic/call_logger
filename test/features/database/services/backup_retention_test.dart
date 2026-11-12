// Διατήρηση δύο γραμμών (Φάση 6): χωριστά όρια για γρήγορα (.db) και πλήρη
// (.zip), και ο απαράβατος κανόνας — το πιο πρόσφατο πλήρες δεν διαγράφεται
// ΠΟΤΕ.
//
//   flutter test test/features/database/services/backup_retention_test.dart

import 'dart:io';

import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/services/backup_retention.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _base = 'call_logger';

Future<File> _makeBackupFile(
  Directory dir,
  String stamp,
  String ext, {
  required DateTime modified,
}) async {
  final f = File(p.join(dir.path, '${stamp}_$_base.$ext'));
  await f.writeAsString('x');
  await f.setLastModified(modified);
  return f;
}

List<String> _names(Directory dir) =>
    dir.listSync().whereType<File>().map((f) => p.basename(f.path)).toList()
      ..sort();

void main() {
  late Directory dir;
  final now = DateTime(2026, 8, 24, 12, 0);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('retention_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });

  DatabaseBackupSettings settingsWith({
    bool quickCountOn = false,
    int quickCount = 48,
    bool quickAgeOn = false,
    int quickAgeDays = 7,
    bool fullCountOn = false,
    int fullCount = 6,
  }) => DatabaseBackupSettings.defaults().copyWith(
    retentionQuickMaxCopiesEnabled: quickCountOn,
    retentionQuickMaxCopies: quickCount,
    retentionQuickMaxAgeEnabled: quickAgeOn,
    retentionQuickMaxAgeDays: quickAgeDays,
    retentionFullMaxCopiesEnabled: fullCountOn,
    retentionFullMaxCopies: fullCount,
  );

  test('το όριο πλήθους των γρήγορων δεν αγγίζει τα πλήρη', () async {
    for (var i = 0; i < 4; i++) {
      await _makeBackupFile(
        dir,
        '2026-08-2${i}_10-00',
        'db',
        modified: now.subtract(Duration(days: 4 - i)),
      );
    }
    await _makeBackupFile(
      dir,
      '2026-08-10_10-00',
      'zip',
      modified: now.subtract(const Duration(days: 14)),
    );

    await BackupRetention.apply(
      destDir: dir,
      baseName: _base,
      settings: settingsWith(quickCountOn: true, quickCount: 2),
      justCreatedPath: p.join(dir.path, '2026-08-23_10-00_$_base.db'),
      now: now,
    );

    final names = _names(dir);
    expect(names.where((n) => n.endsWith('.db')), hasLength(2));
    expect(
      names.where((n) => n.endsWith('.zip')),
      hasLength(1),
      reason: 'Άλλη γραμμή — το παλιό πλήρες δεν είναι «παλιό γρήγορο».',
    );
    expect(names, contains('2026-08-23_10-00_$_base.db'));
    expect(names, contains('2026-08-22_10-00_$_base.db'));
  });

  test(
    'η ηλικία των γρήγορων διαγράφει μόνο γρήγορα πέρα από το όριο',
    () async {
      await _makeBackupFile(
        dir,
        '2026-08-01_10-00',
        'db',
        modified: now.subtract(const Duration(days: 20)),
      );
      await _makeBackupFile(
        dir,
        '2026-08-23_10-00',
        'db',
        modified: now.subtract(const Duration(days: 1)),
      );
      await _makeBackupFile(
        dir,
        '2026-07-01_10-00',
        'zip',
        modified: now.subtract(const Duration(days: 54)),
      );
      final fresh = await _makeBackupFile(
        dir,
        '2026-08-24_12-00',
        'db',
        modified: now,
      );

      await BackupRetention.apply(
        destDir: dir,
        baseName: _base,
        settings: settingsWith(quickAgeOn: true, quickAgeDays: 7),
        justCreatedPath: fresh.path,
        now: now,
      );

      final names = _names(dir);
      expect(names, hasLength(3));
      expect(names, contains('2026-08-23_10-00_$_base.db'));
      expect(names, contains('2026-07-01_10-00_$_base.zip'));
    },
  );

  test('το όριο των πλήρων κρατά τα νεότερα — και ΠΟΤΕ κάτω από ένα', () async {
    for (var i = 0; i < 4; i++) {
      await _makeBackupFile(
        dir,
        '2026-08-2${i}_11-00',
        'zip',
        modified: now.subtract(Duration(days: 4 - i)),
      );
    }

    await BackupRetention.apply(
      destDir: dir,
      baseName: _base,
      settings: settingsWith(fullCountOn: true, fullCount: 2),
      justCreatedPath: p.join(dir.path, '2026-08-23_11-00_$_base.zip'),
      now: now,
    );
    expect(_names(dir).where((n) => n.endsWith('.zip')), hasLength(2));
    expect(_names(dir), contains('2026-08-23_11-00_$_base.zip'));

    // Ακόμη και με όριο 0 (κακή ρύθμιση), το πιο πρόσφατο πλήρες επιβιώνει.
    await BackupRetention.apply(
      destDir: dir,
      baseName: _base,
      settings: settingsWith(fullCountOn: true, fullCount: 0),
      justCreatedPath: p.join(dir.path, '2026-08-23_11-00_$_base.zip'),
      now: now,
    );
    expect(
      _names(dir).where((n) => n.endsWith('.zip')),
      hasLength(1),
      reason: 'Ο απαράβατος κανόνας: το τελευταίο πλήρες μένει.',
    );
    expect(_names(dir), contains('2026-08-23_11-00_$_base.zip'));
  });

  test('ανενεργοί κανόνες δεν διαγράφουν τίποτα', () async {
    await _makeBackupFile(
      dir,
      '2026-08-01_10-00',
      'db',
      modified: now.subtract(const Duration(days: 60)),
    );
    await _makeBackupFile(
      dir,
      '2026-08-02_10-00',
      'zip',
      modified: now.subtract(const Duration(days: 59)),
    );

    await BackupRetention.apply(
      destDir: dir,
      baseName: _base,
      settings: settingsWith(),
      justCreatedPath: p.join(dir.path, '2026-08-02_10-00_$_base.zip'),
      now: now,
    );
    expect(_names(dir), hasLength(2));
  });

  test('άσχετα αρχεία (άλλη βάση, άλλη μορφή) δεν αγγίζονται ποτέ', () async {
    final foreign = File(p.join(dir.path, '2026-08-01_10-00_alli_vasi.db'));
    await foreign.writeAsString('x');
    await foreign.setLastModified(now.subtract(const Duration(days: 90)));
    final random = File(p.join(dir.path, 'simiwseis.txt'));
    await random.writeAsString('x');

    await BackupRetention.apply(
      destDir: dir,
      baseName: _base,
      settings: settingsWith(
        quickCountOn: true,
        quickCount: 1,
        quickAgeOn: true,
        quickAgeDays: 1,
        fullCountOn: true,
        fullCount: 1,
      ),
      justCreatedPath: p.join(dir.path, '2026-08-24_12-00_$_base.db'),
      now: now,
    );
    expect(_names(dir), hasLength(2));
  });

  group('Ρολόι λάθος', () {
    Future<void> makeQuickCopies(int count, {int firstDay = 1}) async {
      for (var i = 0; i < count; i++) {
        final day = firstDay + i;
        await _makeBackupFile(
          dir,
          '2026-08-${day.toString().padLeft(2, '0')}_10-00',
          'db',
          modified: DateTime(2026, 8, day, 10),
        );
      }
    }

    test(
      'ρολόι ένα χρόνο μπροστά: τα παλιά γρήγορα μένουν, και το λέει',
      () async {
        await makeQuickCopies(10);
        final wrongNow = DateTime(2027, 8, 24, 12);
        final fresh = await _makeBackupFile(
          dir,
          '2027-08-24_12-00',
          'db',
          modified: wrongNow,
        );

        final outcome = await BackupRetention.apply(
          destDir: dir,
          baseName: _base,
          settings: settingsWith(quickAgeOn: true, quickAgeDays: 7),
          justCreatedPath: fresh.path,
          now: wrongNow,
        );

        expect(_names(dir), hasLength(11));
        expect(outcome.heldBackByAge, 10);
        expect(outcome.notes.single, contains('10 από τα 10'));
      },
    );

    test('ρολόι μπροστά και στο δεύτερο αντίγραφο: τα παλιά εξακολουθούν να '
        'μένουν', () async {
      await makeQuickCopies(10);
      final wrongNow = DateTime(2027, 8, 24, 12);
      await _makeBackupFile(dir, '2027-08-24_10-00', 'db', modified: wrongNow);
      final fresh = await _makeBackupFile(
        dir,
        '2027-08-24_12-00',
        'db',
        modified: wrongNow,
      );

      await BackupRetention.apply(
        destDir: dir,
        baseName: _base,
        settings: settingsWith(quickAgeOn: true, quickAgeDays: 7),
        justCreatedPath: fresh.path,
        now: wrongNow,
      );

      expect(_names(dir), hasLength(12));
    });

    test(
      'το όριο ηλικίας σβήνει κανονικά όταν φτάνει ακριβώς τα μισά',
      () async {
        await makeQuickCopies(2);
        await makeQuickCopies(2, firstDay: 20);
        final fresh = await _makeBackupFile(
          dir,
          '2026-08-24_12-00',
          'db',
          modified: now,
        );

        final outcome = await BackupRetention.apply(
          destDir: dir,
          baseName: _base,
          settings: settingsWith(quickAgeOn: true, quickAgeDays: 7),
          justCreatedPath: fresh.path,
          now: now,
        );

        expect(_names(dir), hasLength(3));
        expect(outcome.notes, isEmpty);
      },
    );

    test('ρολόι πίσω: το όριο πλήθους δεν σβήνει το γρήγορο που μόλις έγινε, '
        'ούτε τα πιο πρόσφατα', () async {
      await makeQuickCopies(3, firstDay: 20);
      final wrongNow = DateTime(2025, 8, 24, 12);
      final fresh = await _makeBackupFile(
        dir,
        '2025-08-24_12-00',
        'db',
        modified: wrongNow,
      );

      await BackupRetention.apply(
        destDir: dir,
        baseName: _base,
        settings: settingsWith(quickCountOn: true, quickCount: 3),
        justCreatedPath: fresh.path,
        now: wrongNow,
      );

      expect(_names(dir), hasLength(4));
      expect(await fresh.exists(), isTrue);
    });

    test('ρολόι πίσω: το πλήρες που μόλις έγινε μένει, μαζί με το πιο πρόσφατο '
        'κατά την ώρα του αρχείου', () async {
      final newest = await _makeBackupFile(
        dir,
        '2026-08-20_10-00',
        'zip',
        modified: DateTime(2026, 8, 20, 10),
      );
      final wrongNow = DateTime(2025, 8, 24, 12);
      final fresh = await _makeBackupFile(
        dir,
        '2025-08-24_12-00',
        'zip',
        modified: wrongNow,
      );

      await BackupRetention.apply(
        destDir: dir,
        baseName: _base,
        settings: settingsWith(fullCountOn: true, fullCount: 1),
        justCreatedPath: fresh.path,
        now: wrongNow,
      );

      expect(await fresh.exists(), isTrue);
      expect(await newest.exists(), isTrue);
    });
  });

  test('αντίγραφο που δεν σβήνεται: το αποτέλεσμα το ονομάζει', () async {
    final locked = await _makeBackupFile(
      dir,
      '2026-08-01_10-00',
      'db',
      modified: DateTime(2026, 8, 1, 10),
    );
    Process.runSync('attrib', ['+r', locked.path]);
    addTearDown(() => Process.runSync('attrib', ['-r', locked.path]));
    await _makeBackupFile(
      dir,
      '2026-08-20_10-00',
      'db',
      modified: DateTime(2026, 8, 20, 10),
    );
    final fresh = await _makeBackupFile(
      dir,
      '2026-08-24_12-00',
      'db',
      modified: now,
    );

    final outcome = await BackupRetention.apply(
      destDir: dir,
      baseName: _base,
      settings: settingsWith(quickAgeOn: true, quickAgeDays: 7),
      justCreatedPath: fresh.path,
      now: now,
    );

    expect(await locked.exists(), isTrue);
    expect(outcome.notDeleted, [p.basename(locked.path)]);
    expect(outcome.notes.single, contains(p.basename(locked.path)));
  });
}
