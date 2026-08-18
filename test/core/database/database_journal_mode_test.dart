// Τρόπος ημερολογίου: κλασικό αντί για WAL, παντού.
//
// Το WAL απαιτεί κοινή μνήμη (`-shm`) ανάμεσα στις συνδέσεις, και η κοινή
// μνήμη δεν ταξιδεύει από δίκτυο. Η επίσημη θέση του SQLite: όλες οι
// συνδέσεις WAL πρέπει να είναι στο ίδιο μηχάνημα.
//
// Ο κρίσιμος έλεγχος εδώ είναι ο ΤΡΙΤΟΣ: η μετάβαση από WAL δεν επιτρέπεται
// να χάσει ό,τι ζει ακόμη μέσα στο `-wal`. Στην πραγματική βάση μετρήθηκαν
// 6 κλήσεις, 1 εκκρεμότητα και 16 εγγραφές ιστορικού να ζουν μόνο εκεί.
//
//   flutter test test/core/database/database_journal_mode_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_access_probe.dart';
import 'package:call_logger/core/database/database_journal_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_journal_mode_test');
  });

  group('ποιος τρόπος επιλέγεται', () {
    test('δικτυακή διαδρομή: κλασικό ημερολόγιο', () {
      expect(
        resolveDatabaseJournalMode(
          r'\\gnk.local\Departments\TPO\Call Logger\call_logger.db',
        ),
        DatabaseJournalMode.delete,
      );
    });

    test('τοπική διαδρομή: ΕΠΙΣΗΣ κλασικό ημερολόγιο', () {
      // Ένας τρόπος, όχι δύο. Με WAL τοπικά, μια κακή ομαδοποίηση εγγραφών
      // κοστίζει 2 δευτερόλεπτα και δεν τη βλέπεις ποτέ· με ημερολόγιο
      // κοστίζει 38. Δοκιμάζουμε ό,τι τρέχουμε.
      expect(
        resolveDatabaseJournalMode(r'C:\Users\x\Documents\call_logger.db'),
        DatabaseJournalMode.delete,
      );
    });
  });

  group('εφαρμογή σε πραγματικό αρχείο', () {
    test('νέα βάση ξεκινά σε κλασικό ημερολόγιο', () async {
      final path = p.join(tempDir.path, 'nea.db');
      final db = await openDatabase(path, singleInstance: false);
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');

      final outcome = await applyDatabaseJournalMode(db, path);

      expect(outcome.applied, isTrue);
      expect(outcome.effective, DatabaseJournalMode.delete);
      expect(await readDatabaseJournalMode(db), DatabaseJournalMode.delete);
      await db.close();
    });

    test('η μετάβαση από WAL ΔΕΝ χάνει ό,τι ζει στο -wal', () async {
      final path = p.join(tempDir.path, 'metavasi.db');
      final db = await openDatabase(path, singleInstance: false);
      await db.execute('PRAGMA journal_mode = WAL');
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, note TEXT)');

      // Αρκετές εγγραφές ώστε να μείνουν αδημοσίευτες μέσα στο -wal.
      for (var i = 0; i < 200; i++) {
        await db.insert('t', {'note': 'κλήση $i'});
      }
      expect(await readDatabaseJournalMode(db), DatabaseJournalMode.wal);
      final wal = File('$path-wal');
      expect(await wal.exists(), isTrue, reason: 'χρειάζεται ζωντανό -wal');
      expect((await wal.stat()).size, greaterThan(0));

      final outcome = await applyDatabaseJournalMode(db, path);

      expect(outcome.applied, isTrue);
      expect(outcome.previous, DatabaseJournalMode.wal);
      expect(outcome.effective, DatabaseJournalMode.delete);

      // Το κρίσιμο: όλα τα δεδομένα επέζησαν.
      final rows = await db.rawQuery('SELECT count(*) AS n FROM t');
      expect(rows.first['n'], 200);
      await db.close();

      // Και ζουν πλέον στο ΚΥΡΙΟ αρχείο, χωρίς συνοδό.
      expect(await wal.exists(), isFalse);
      final reopened = await openDatabase(path, singleInstance: false);
      final again = await reopened.rawQuery('SELECT count(*) AS n FROM t');
      expect(again.first['n'], 200);
      await reopened.close();
    });

    test('η αλλαγή γράφεται στο αρχείο και επιβιώνει του κλεισίματος', () async {
      // Ο τρόπος ημερολογίου είναι ιδιότητα του ΑΡΧΕΙΟΥ, όχι της σύνδεσης —
      // αντίθετα με την αναμονή κλειδώματος.
      final path = p.join(tempDir.path, 'epiviosi.db');
      final first = await openDatabase(path, singleInstance: false);
      await first.execute('PRAGMA journal_mode = WAL');
      await first.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await applyDatabaseJournalMode(first, path);
      await first.close();

      final second = await openDatabase(path, singleInstance: false);
      expect(await readDatabaseJournalMode(second), DatabaseJournalMode.delete);
      await second.close();
    });

    test('επανάληψη σε ήδη σωστή βάση δεν αλλάζει τίποτα', () async {
      final path = p.join(tempDir.path, 'idempotent.db');
      final db = await openDatabase(path, singleInstance: false);
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');

      await applyDatabaseJournalMode(db, path);
      final second = await applyDatabaseJournalMode(db, path);

      expect(second.applied, isTrue);
      expect(second.previous, DatabaseJournalMode.delete);
      expect(second.changed, isFalse);
      await db.close();
    });
  });

  group('όταν η αλλαγή δεν περνά', () {
    test('βάση που κρατά άλλη σύνδεση: δεν σφάλλει, το αναφέρει', () async {
      // Το εύρημα που παραλίγο να περάσει απαρατήρητο: το
      // «PRAGMA journal_mode = DELETE» ΠΕΤΑΕΙ «database is locked» όταν κάποιος
      // άλλος κρατά τη βάση σε WAL. Αν η εξαίρεση ανέβαινε, ένας συνάδελφος με
      // ανοιχτή την κοινόχρηστη βάση θα εμπόδιζε ΟΛΟΥΣ να την ανοίξουν.
      final path = p.join(tempDir.path, 'piasmeni.db');
      final holder = await openDatabase(path, singleInstance: false);
      await holder.execute('PRAGMA journal_mode = WAL');
      await holder.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await holder.rawInsert('INSERT INTO t (id) VALUES (1)');
      // Ανοιχτή εγγραφή: η βάση είναι πιασμένη.
      await holder.execute('BEGIN IMMEDIATE');
      await holder.rawInsert('INSERT INTO t (id) VALUES (2)');

      final second = await openDatabase(path, singleInstance: false);
      final outcome = await applyDatabaseJournalMode(second, path);

      // Ό,τι κι αν έγινε, δεν πετάχτηκε εξαίρεση και η σύνδεση ζει.
      expect(outcome.requested, DatabaseJournalMode.delete);
      if (!outcome.applied) {
        expect(outcome.effective, DatabaseJournalMode.wal);
        expect(outcome.error, isNotNull);
      }
      expect(await second.rawQuery('SELECT 1'), isNotEmpty);

      try {
        await holder.execute('COMMIT');
      } catch (_) {}
      await second.close();
      await holder.close();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('τα διαγνωστικά βλέπουν το -journal', () {
    test('ξεχασμένο ημερολόγιο αναίρεσης αναφέρεται ως προειδοποίηση', () async {
      // Ένα «-journal» πριν από το άνοιγμα σημαίνει ότι προηγούμενη εγγραφή
      // δεν ολοκληρώθηκε: εξηγεί αργό άνοιγμα και μαρτυρά κατάρρευση. Ως τώρα
      // τα διαγνωστικά έβλεπαν μόνο «-wal» και «-shm», οπότε ήταν αόρατο.
      final path = p.join(tempDir.path, 'me_journal.db');
      final db = await openDatabase(path, singleInstance: false);
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.close();
      await File('$path-journal').writeAsBytes(List<int>.filled(512, 0));

      final report = await const DatabaseAccessProbe().probe(path);

      expect(report.humanReadable, contains('-journal'));
      expect(
        report.findings.any((f) => f.code == 'hot_journal_present'),
        isTrue,
      );
      expect(report.hasWarnings, isTrue);
    });

    test('χωρίς ημερολόγιο δεν παράγεται θόρυβος', () async {
      final path = p.join(tempDir.path, 'xoris_journal.db');
      final db = await openDatabase(path, singleInstance: false);
      await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.close();

      final report = await const DatabaseAccessProbe().probe(path);

      expect(
        report.findings.any((f) => f.code == 'hot_journal_present'),
        isFalse,
      );
    });
  });
}
