// Ανίχνευση εξωτερικής αντικατάστασης του αρχείου βάσης εν λειτουργία.
//
// Το κρίσιμο ζεύγος: η αντιγραφή άλλης βάσης πάνω στην ενεργή ΠΡΕΠΕΙ να
// ανιχνεύεται, ενώ η κανονική εγγραφή —δική μας ή άλλου μηχανήματος— ΔΕΝ
// επιτρέπεται να δώσει συναγερμό. Η κοινόχρηστη λειτουργία εξαρτάται από το
// δεύτερο σκέλος όσο η ασφάλεια από το πρώτο.
//
//   flutter test test/core/database/database_file_identity_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_file_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Δημιουργεί αρχείο βάσης με [rows] εγγραφές στον πίνακα `sample`.
Future<String> _createDb(Directory dir, String name, int rows) async {
  final path = p.join(dir.path, name);
  final db = await openDatabase(path, singleInstance: false);
  await db.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY, note TEXT)');
  for (var i = 0; i < rows; i++) {
    await db.insert('sample', {'note': 'γραμμή $i'});
  }
  await db.close();
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_identity_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('ανάγνωση ταυτότητας', () {
    test('διαβάζει την κεφαλίδα πραγματικού αρχείου βάσης', () async {
      final path = await _createDb(tempDir, 'a.db', 3);

      final identity = await readDatabaseFileIdentity(path);

      expect(identity, isNotNull);
      expect(identity!.pageSize, greaterThan(0));
      expect(identity.fileSize, greaterThanOrEqualTo(100));
      expect(identity.pageCount, greaterThan(0));
    });

    test('αρχείο που δεν είναι SQLite δίνει άγνοια, όχι σκουπίδια', () async {
      final path = p.join(tempDir.path, 'not_a_db.txt');
      await File(path).writeAsString('x' * 500);

      expect(await readDatabaseFileIdentity(path), isNull);
    });

    test('ανύπαρκτο αρχείο δίνει άγνοια χωρίς εξαίρεση', () async {
      final path = p.join(tempDir.path, 'λείπει.db');

      expect(await readDatabaseFileIdentity(path), isNull);
    });
  });

  group('το αδύνατο ανιχνεύεται', () {
    test(
      'αντιγραφή ΑΛΛΗΣ βάσης πάνω στην ενεργή ανιχνεύεται ως αντικατάσταση',
      () async {
        // Το πραγματικό περιστατικό 11/08/2026: με ανοιχτή την εφαρμογή,
        // αντιγραφή άλλου Hospital.db πάνω στο ενεργό.
        final activePath = await _createDb(tempDir, 'ενεργή.db', 40);
        final otherPath = await _createDb(tempDir, 'άλλη.db', 2);

        final before = await readDatabaseFileIdentity(activePath);
        await File(otherPath).copy(activePath);

        final verdict = await verifyDatabaseFileIdentity(
          path: activePath,
          before: before,
          secondLookDelay: Duration.zero,
        );

        expect(verdict, DatabaseIdentityVerdict.replaced);
      },
    );

    test('μετρητής αλλαγών προς τα πίσω = αντικατάσταση', () {
      const before = DatabaseFileIdentity(
        fileSize: 8192,
        pageSize: 4096,
        changeCounter: 90,
        schemaCookie: 5,
        pageCount: 2,
      );
      const after = DatabaseFileIdentity(
        fileSize: 8192,
        pageSize: 4096,
        changeCounter: 12,
        schemaCookie: 5,
        pageCount: 2,
      );

      expect(
        compareDatabaseFileIdentity(before: before, after: after),
        DatabaseIdentityVerdict.replaced,
      );
    });

    test('ακίνητος μετρητής με αλλαγμένο μέγεθος = αντικατάσταση', () {
      // Χωρίς εγγραφή δεν μπορεί να άλλαξε το μέγεθος: το αρχείο είναι άλλο.
      const before = DatabaseFileIdentity(
        fileSize: 8192,
        pageSize: 4096,
        changeCounter: 30,
        schemaCookie: 5,
        pageCount: 2,
      );
      const after = DatabaseFileIdentity(
        fileSize: 20480,
        pageSize: 4096,
        changeCounter: 30,
        schemaCookie: 5,
        pageCount: 5,
      );

      expect(
        compareDatabaseFileIdentity(before: before, after: after),
        DatabaseIdentityVerdict.replaced,
      );
    });

    test('αλλαγή μεγέθους σελίδας = αντικατάσταση', () {
      const before = DatabaseFileIdentity(
        fileSize: 8192,
        pageSize: 4096,
        changeCounter: 30,
        schemaCookie: 5,
        pageCount: 2,
      );
      const after = DatabaseFileIdentity(
        fileSize: 8192,
        pageSize: 8192,
        changeCounter: 31,
        schemaCookie: 5,
        pageCount: 1,
      );

      expect(
        compareDatabaseFileIdentity(before: before, after: after),
        DatabaseIdentityVerdict.replaced,
      );
    });
  });

  group('η κοινόχρηστη λειτουργία δεν ενοχλείται', () {
    test('κανονική εγγραφή στη βάση ΔΕΝ δίνει συναγερμό', () async {
      final path = await _createDb(tempDir, 'κοινή.db', 5);
      final before = await readDatabaseFileIdentity(path);

      // Ό,τι ακριβώς κάνει ένας συνάδελφος από άλλο μηχάνημα.
      final db = await openDatabase(path, singleInstance: false);
      for (var i = 0; i < 50; i++) {
        await db.insert('sample', {'note': 'νέα εγγραφή $i'});
      }
      await db.close();

      final verdict = await verifyDatabaseFileIdentity(
        path: path,
        before: before,
        secondLookDelay: Duration.zero,
      );

      expect(verdict, DatabaseIdentityVerdict.unchangedOrNormal);
    });

    test('αλλαγή σχήματος ΔΕΝ δίνει συναγερμό', () async {
      final path = await _createDb(tempDir, 'σχήμα.db', 3);
      final before = await readDatabaseFileIdentity(path);

      final db = await openDatabase(path, singleInstance: false);
      await db.execute('ALTER TABLE sample ADD COLUMN extra TEXT');
      await db.close();

      final verdict = await verifyDatabaseFileIdentity(
        path: path,
        before: before,
        secondLookDelay: Duration.zero,
      );

      expect(verdict, DatabaseIdentityVerdict.unchangedOrNormal);
    });

    test('καμία απολύτως αλλαγή ΔΕΝ δίνει συναγερμό', () async {
      final path = await _createDb(tempDir, 'ήσυχη.db', 4);
      final before = await readDatabaseFileIdentity(path);

      final verdict = await verifyDatabaseFileIdentity(
        path: path,
        before: before,
        secondLookDelay: Duration.zero,
      );

      expect(verdict, DatabaseIdentityVerdict.unchangedOrNormal);
    });

    test('άφταστο αρχείο δίνει άγνοια — ποτέ συναγερμό', () async {
      const before = DatabaseFileIdentity(
        fileSize: 8192,
        pageSize: 4096,
        changeCounter: 30,
        schemaCookie: 5,
        pageCount: 2,
      );

      final verdict = await verifyDatabaseFileIdentity(
        path: p.join(tempDir.path, 'δικτυακή_άφταστη.db'),
        before: before,
        secondLookDelay: Duration.zero,
      );

      expect(verdict, DatabaseIdentityVerdict.unknown);
    });

    test('χωρίς αρχικό στιγμιότυπο δεν κατηγορεί κανέναν', () async {
      final path = await _createDb(tempDir, 'χωρίς_αφετηρία.db', 2);

      final verdict = await verifyDatabaseFileIdentity(
        path: path,
        before: null,
        secondLookDelay: Duration.zero,
      );

      expect(verdict, DatabaseIdentityVerdict.unknown);
    });
  });

  group('δεύτερη ματιά', () {
    test(
      'στιγμιαία ασυνέπεια που αποκαθίσταται ΔΕΝ γίνεται συναγερμός',
      () async {
        const before = DatabaseFileIdentity(
          fileSize: 8192,
          pageSize: 4096,
          changeCounter: 30,
          schemaCookie: 5,
          pageCount: 2,
        );
        // Πρώτη ανάγνωση: μετρητής προς τα πίσω (torn read).
        // Δεύτερη: ομαλή εικόνα.
        const torn = DatabaseFileIdentity(
          fileSize: 8192,
          pageSize: 4096,
          changeCounter: 3,
          schemaCookie: 5,
          pageCount: 2,
        );
        const settled = DatabaseFileIdentity(
          fileSize: 8192,
          pageSize: 4096,
          changeCounter: 31,
          schemaCookie: 5,
          pageCount: 2,
        );
        final reads = <DatabaseFileIdentity>[torn, settled];
        var index = 0;

        final verdict = await verifyDatabaseFileIdentity(
          path: 'ό,τι νά ναι.db',
          before: before,
          secondLookDelay: Duration.zero,
          read: (_) async => reads[index++],
        );

        expect(verdict, DatabaseIdentityVerdict.unchangedOrNormal);
        expect(index, 2, reason: 'πρέπει να έγιναν ακριβώς δύο αναγνώσεις');
      },
    );

    test('μία μόνο ανάγνωση όταν όλα είναι ομαλά', () async {
      const before = DatabaseFileIdentity(
        fileSize: 8192,
        pageSize: 4096,
        changeCounter: 30,
        schemaCookie: 5,
        pageCount: 2,
      );
      var reads = 0;

      await verifyDatabaseFileIdentity(
        path: 'ό,τι νά ναι.db',
        before: before,
        secondLookDelay: Duration.zero,
        read: (_) async {
          reads++;
          return before;
        },
      );

      expect(reads, 1, reason: 'ο ήσυχος δρόμος δεν πληρώνει δεύτερη ανάγνωση');
    });
  });
}
