// Τα ίχνη σύνδεσης: μία γραμμή ανά χρήστη ΚΑΙ σταθμό, χωρίς ιστορικό.
//
//   flutter test test/core/database/operator_presence_repository_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/operator_presence_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Ίχνη σύνδεσης χρηστών', () {
    late Database db;
    late OperatorPresenceRepository repository;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 50);
      repository = OperatorPresenceRepository(db);
    });

    tearDown(() async => db.close());

    test('η μετάπτωση v50 φτιάχνει τον πίνακα', () async {
      final tables = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', OperatorPresenceRepository.tableName],
      );

      expect(tables, hasLength(1));
    });

    test('ο ίδιος σταθμός ανανεώνεται, δεν συσσωρεύεται', () async {
      // Αλλιώς ο πίνακας θα γινόταν ημερολόγιο: ένας χτύπος το λεπτό, για
      // πάντα, σε βάση που ζει σε δικτυακό φάκελο.
      await repository.touch(
        operatorId: 1,
        station: 'ΤΠΕ-03',
        at: DateTime(2026, 8, 21, 10),
      );
      await repository.touch(
        operatorId: 1,
        station: 'ΤΠΕ-03',
        at: DateTime(2026, 8, 21, 11),
      );

      final all = await repository.getAll();

      expect(all, hasLength(1));
      expect(all.single.lastSeenAt, DateTime(2026, 8, 21, 11));
    });

    test('δεύτερος σταθμός του ίδιου χρήστη κρατιέται ξεχωριστά', () async {
      await repository.touch(
        operatorId: 1,
        station: 'ΤΠΕ-03',
        at: DateTime(2026, 8, 21, 10),
      );
      await repository.touch(
        operatorId: 1,
        station: 'ΓΡΑΜΜΑΤΕΙΑ-01',
        at: DateTime(2026, 8, 21, 10, 30),
      );

      final marks = await repository.forOperator(1);

      expect(marks, hasLength(2));
      expect(
        marks.map((m) => m.station),
        containsAll(['ΤΠΕ-03', 'ΓΡΑΜΜΑΤΕΙΑ-01']),
      );
    });

    test('τα ίχνη άλλου χρήστη δεν ανακατεύονται', () async {
      await repository.touch(
        operatorId: 1,
        station: 'ΤΠΕ-03',
        at: DateTime(2026, 8, 21, 10),
      );
      await repository.touch(
        operatorId: 2,
        station: 'ΤΠΕ-03',
        at: DateTime(2026, 8, 21, 10),
      );

      expect(await repository.forOperator(1), hasLength(1));
      expect(await repository.forOperator(2), hasLength(1));
      expect(await repository.getAll(), hasLength(2));
    });

    test('κενό όνομα σταθμού δεν γράφεται καθόλου', () async {
      // Ένα ίχνος χωρίς σταθμό δεν απαντά σε τίποτα — καλύτερα να λείπει παρά
      // να γεμίσει η κάρτα με κενές γραμμές.
      await repository.touch(
        operatorId: 1,
        station: '   ',
        at: DateTime(2026, 8, 21, 10),
      );

      expect(await repository.getAll(), isEmpty);
    });

    test('χαλασμένη γραμμή αγνοείται αντί να ρίξει την οθόνη', () async {
      await db.insert(OperatorPresenceRepository.tableName, {
        'operator_id': 1,
        'station': 'ΤΠΕ-03',
        'last_seen_at': 'όχι-ημερομηνία',
      });
      await repository.touch(
        operatorId: 2,
        station: 'ΚΑΛΟΣ',
        at: DateTime(2026, 8, 21, 10),
      );

      final all = await repository.getAll();

      expect(all, hasLength(1));
      expect(all.single.station, 'ΚΑΛΟΣ');
    });
  });
}
