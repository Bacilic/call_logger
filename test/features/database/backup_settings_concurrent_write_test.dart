// Σύνθετες ρυθμίσεις που ζουν σε ΕΝΑ κλειδί: το «δέμα» των αντιγράφων κρατά
// ΚΑΙ τις επιλογές του διαχειριστή ΚΑΙ τη λογιστική εκτέλεσης (ποιο αντίγραφο
// πάρθηκε, πότε, ως ποια αλλαγή). Η οθόνη ρυθμίσεων γράφει ολόκληρο το δέμα από
// την εικόνα που φόρτωσε — οπότε ένα τσεκάρισμα σε παλιά ανοιχτή οθόνη σβήνει τη
// σφραγίδα του αντιγράφου που μόλις πήρε το άλλο μηχάνημα, και ο χρονιστής
// ξαναπαίρνει αντίγραφο που υπάρχει ήδη.
//
//   flutter test test/features/database/backup_settings_concurrent_write_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/services/active_backup_settings.dart';
import 'package:call_logger/features/database/utils/backup_schedule_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Ρυθμίσεις αντιγράφων — δύο μηχανήματα στο ίδιο κλειδί', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('backup_settings_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/settings.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await SettingsRepository(
        db,
      ).saveSetting(ActiveBackupSettings.migrationMarkerKey, '1');
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [DatabaseBackupSettings.appSettingsKey],
      );
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    /// Η οθόνη ρυθμίσεων άνοιξε στις 09:00 και κρατά αυτή την εικόνα.
    Future<DatabaseBackupSettings> screenOpenedAtNine() async {
      final initial = DatabaseBackupSettings.defaults().copyWith(
        destinationDirectory: r'\\server\backups',
        includeLexicon: false,
      );
      await ActiveBackupSettings.overwriteAll(initial);
      return (await ActiveBackupSettings.read());
    }

    /// Ο χρονιστής του ΑΛΛΟΥ μηχανήματος παίρνει αντίγραφο και το σφραγίζει.
    Future<void> otherMachineTakesBackup() async {
      final gate = await ActiveBackupSettings.readWithRaw();
      final stamped = gate.settings.copyWith(
        lastBackupAuditId: 5120,
        lastBackupAttempt: DateTime(2026, 8, 25, 13, 40),
        lastBackupStatus: BackupScheduleStatus.success,
      );
      final won = await ActiveBackupSettings.tryReplace(
        expectedRaw: gate.raw,
        replacement: stamped,
      );
      expect(won, isTrue, reason: 'Προϋπόθεση: το άλλο μηχάνημα έγραψε');
    }

    test('το τσεκάρισμα δεν σβήνει τη σφραγίδα του άλλου', () async {
      final asScreenSawIt = await screenOpenedAtNine();
      expect(asScreenSawIt.lastBackupAuditId, isNull);
      await otherMachineTakesBackup();

      // Ο διαχειριστής τσεκάρει «Λεξικό» πάνω στην παλιά εικόνα του.
      await ActiveBackupSettings.update(
        (current) => current.copyWith(includeLexicon: true),
      );

      final stored = await ActiveBackupSettings.read();
      expect(
        stored.includeLexicon,
        isTrue,
        reason: 'η δική μου αλλαγή γράφτηκε',
      );
      expect(
        stored.lastBackupAuditId,
        5120,
        reason: 'η σφραγίδα του αντιγράφου δεν επιτρέπεται να χαθεί',
      );
      expect(stored.lastBackupAttempt, DateTime(2026, 8, 25, 13, 40));
      expect(stored.lastBackupStatus, BackupScheduleStatus.success);
    });

    test('η αλλαγή του συναδέλφου σε ΑΛΛΟ πεδίο επιβιώνει', () async {
      await screenOpenedAtNine();

      // Ο συνάδελφος, από το άλλο μηχάνημα, αλλάζει τον φάκελο προορισμού.
      final gate = await ActiveBackupSettings.readWithRaw();
      await ActiveBackupSettings.tryReplace(
        expectedRaw: gate.raw,
        replacement: gate.settings.copyWith(
          destinationDirectory: r'\\server\backups\2026',
        ),
      );

      await ActiveBackupSettings.update(
        (current) => current.copyWith(includeLexicon: true),
      );

      final stored = await ActiveBackupSettings.read();
      expect(stored.includeLexicon, isTrue);
      expect(
        stored.destinationDirectory,
        r'\\server\backups\2026',
        reason: 'δεν άγγιξα τον φάκελο, άρα δεν τον επαναφέρω',
      );
    });

    test('η δική μου αλλαγή κερδίζει στο ΙΔΙΟ πεδίο', () async {
      await screenOpenedAtNine();

      final gate = await ActiveBackupSettings.readWithRaw();
      await ActiveBackupSettings.tryReplace(
        expectedRaw: gate.raw,
        replacement: gate.settings.copyWith(includeLexicon: true),
      );

      // Εγώ το ξετσεκάρω ρητά — η ρητή μου πρόθεση δεν αγνοείται.
      await ActiveBackupSettings.update(
        (current) => current.copyWith(includeLexicon: false),
      );

      expect((await ActiveBackupSettings.read()).includeLexicon, isFalse);
    });

    test('χωρίς αποθηκευμένη τιμή η εγγραφή περνά κανονικά', () async {
      await ActiveBackupSettings.update(
        (current) => current.copyWith(includeLampDb: true),
      );

      expect((await ActiveBackupSettings.read()).includeLampDb, isTrue);
    });
  });
}
