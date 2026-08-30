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

      await BackupRetention.apply(
        destDir: dir,
        baseName: _base,
        settings: settingsWith(quickAgeOn: true, quickAgeDays: 7),
        now: now,
      );

      final names = _names(dir);
      expect(names, hasLength(2));
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
      now: now,
    );
    expect(_names(dir).where((n) => n.endsWith('.zip')), hasLength(2));
    expect(_names(dir), contains('2026-08-23_11-00_$_base.zip'));

    // Ακόμη και με όριο 0 (κακή ρύθμιση), το πιο πρόσφατο πλήρες επιβιώνει.
    await BackupRetention.apply(
      destDir: dir,
      baseName: _base,
      settings: settingsWith(fullCountOn: true, fullCount: 0),
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
      now: now,
    );
    expect(_names(dir), hasLength(2));
  });
}
