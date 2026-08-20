// Ο πίνακας των χρηστών της εφαρμογής (`operators`) και οι ιδιότητες που τον
// κάνουν ασφαλή για κοινόχρηστη βάση: γεννιέται με τη μετάπτωση v47 και δεν
// δεσμεύει κανέναν υπάρχοντα πίνακα.
//
//   flutter test test/core/database/operators_schema_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Μετάπτωση v47 — πίνακας χρηστών εφαρμογής', () {
    late Database db;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    });

    tearDown(() async {
      await db.close();
    });

    Future<Set<String>> tableNames() async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      return {for (final row in rows) row['name'] as String};
    }

    test('βάση της προηγούμενης έκδοσης αποκτά τον πίνακα', () async {
      expect(await tableNames(), isNot(contains('operators')));

      await onDatabaseUpgradeSquashed(db, 46, 47);

      expect(await tableNames(), contains('operators'));
    });

    test('η μετάπτωση ξανατρέχει χωρίς παράπονο', () async {
      await onDatabaseUpgradeSquashed(db, 46, 47);
      await onDatabaseUpgradeSquashed(db, 46, 47);

      expect(await tableNames(), contains('operators'));
    });

    test('η μετάπτωση δεν δημιουργεί κανένα προφίλ', () async {
      // Η μετάπτωση δεν ξέρει ποιος την τρέχει· ένα προφίλ εδώ θα έγραφε λάθος
      // όνομα στο Ιστορικό όλων.
      await onDatabaseUpgradeSquashed(db, 46, 47);

      expect(await OperatorRepository(db).count(), 0);
    });

    test(
      'ο πίνακας δεν δεσμεύει κανέναν άλλο — παλιά έκδοση ανοίγει τη βάση',
      () async {
        // Ένας δεσμός προς πίνακα που γνωρίζει η παλιά έκδοση θα εμπόδιζε τις
        // δικές της διαγραφές, και τότε η βάση θα της απαγορευόταν.
        await onDatabaseUpgradeSquashed(db, 46, 47);

        final foreignKeys = await db.rawQuery(
          'PRAGMA foreign_key_list(operators)',
        );

        expect(foreignKeys, isEmpty);
      },
    );

    test('ένας λογαριασμός Windows δεν μοιράζεται σε δύο προφίλ', () async {
      await onDatabaseUpgradeSquashed(db, 46, 47);
      final repository = OperatorRepository(db);
      await repository.insert(
        Operator(
          displayName: 'Πρώτος',
          windowsAccount: 'vdrosos',
          createdAt: DateTime(2026, 8, 19),
        ),
      );

      await expectLater(
        repository.insert(
          Operator(
            displayName: 'Δεύτερος',
            windowsAccount: 'vdrosos',
            createdAt: DateTime(2026, 8, 19),
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('τα προφίλ χωρίς λογαριασμό είναι όσα θέλει κανείς', () async {
      await onDatabaseUpgradeSquashed(db, 46, 47);
      final repository = OperatorRepository(db);

      await repository.insert(
        Operator(displayName: 'Αυτόνομο Α', createdAt: DateTime(2026, 8, 19)),
      );
      await repository.insert(
        Operator(displayName: 'Αυτόνομο Β', createdAt: DateTime(2026, 8, 19)),
      );

      expect(await repository.count(), 2);
    });
  });
}
