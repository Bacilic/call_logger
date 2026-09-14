// Τα ίχνη σύνδεσης: μία γραμμή ανά χρήστη ΚΑΙ σταθμό, χωρίς ιστορικό.
//
//   flutter test test/core/database/operator_presence_repository_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/operator_presence_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

void main() {
  group('Ίχνη σύνδεσης χρηστών', () {
    late Database db;
    late OperatorPresenceRepository repository;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      // Ως την v50 χτίζεται ο πίνακας· οι δύο επόμενες που τον αφορούν
      // καλούνται ρητά. Οι ενδιάμεσες θέλουν πίνακες (Ιστορικό) που αυτό το
      // τεστ δεν έχει λόγο να στήσει.
      await onDatabaseUpgradeSquashed(db, 46, 50);
      await migrateDatabaseToV52(db);
      await migrateDatabaseToV60(db);
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

    test('πόσοι διαφορετικοί υπολογιστές έχουν ανοίξει τη βάση', () async {
      // Το αυθεντικό κριτήριο «κοινόχρηστη ή όχι»: όχι η διαδρομή ούτε το
      // όνομα, αλλά το αν το αρχείο έχει δει παραπάνω από έναν σταθμό.
      expect(await repository.countDistinctStations(), 0);

      await repository.touch(
        operatorId: 1,
        station: 'ΤΠΕ-03',
        at: DateTime(2026, 8, 21, 10),
      );
      expect(await repository.countDistinctStations(), 1);

      // Δεύτερος χρήστης στον ΙΔΙΟ υπολογιστή: εξακολουθεί να είναι ένας.
      await repository.touch(
        operatorId: 2,
        station: 'ΤΠΕ-03',
        at: DateTime(2026, 8, 21, 11),
      );
      expect(
        await repository.countDistinctStations(),
        1,
        reason:
            'Δύο προφίλ στον ίδιο υπολογιστή δεν κάνουν τη βάση κοινόχρηστη.',
      );

      await repository.touch(
        operatorId: 2,
        station: 'ΤΠΕ-07',
        at: DateTime(2026, 8, 21, 12),
      );
      expect(await repository.countDistinctStations(), 2);
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

    test('η μετάπτωση v60 προσθέτει τη στήλη της έκδοσης', () async {
      final info = await db.rawQuery('PRAGMA table_info(operator_presence)');
      final columns = info.map((r) => r['name'] as String).toSet();

      expect(columns, contains('app_version'));
    });

    test('ο παλμός κρατά την έκδοση που τρέχει η συνεδρία', () async {
      await repository.touch(
        operatorId: 1,
        station: 'TEP-02',
        instance: r'C:pp.exe',
        appVersion: '1.60.0',
        at: DateTime(2026, 9, 14, 12),
      );

      final mark = (await repository.getAll()).single;
      expect(mark.appVersion, '1.60.0');
    });

    test('κενή έκδοση γράφεται ως απουσία, όχι ως κενό κείμενο', () async {
      // Όταν το σύστημα δεν δίνει έκδοση, η στήλη μένει άδεια αντί να
      // κρατήσει κενό κείμενο που θα έμπαινε στη λίστα ως γραμμή-φάντασμα.
      await repository.touch(
        operatorId: 1,
        station: 'TEP-02',
        instance: r'C:pp.exe',
        appVersion: '   ',
        at: DateTime(2026, 9, 14, 12),
      );

      expect((await repository.getAll()).single.appVersion, isNull);
    });

    test('η ανάγνωση με ονόματα φέρνει τον άνθρωπο μαζί με το ίχνος', () async {
      await db.insert('operators', {
        'id': 7,
        'display_name': 'Βαρβάρα',
        'is_admin': 0,
        'is_active': 1,
        'created_at': '2026-09-14T12:00:00.000',
      });
      await repository.touch(
        operatorId: 7,
        station: 'TEP-02',
        instance: r'C:pp.exe',
        at: DateTime(2026, 9, 14, 12),
      );
      // Ίχνος χρήστη που έχει διαγραφεί: μένει στη λίστα, χωρίς όνομα.
      await repository.touch(
        operatorId: 99,
        station: 'GRAM-05',
        instance: r'C:\other.exe',
        at: DateTime(2026, 9, 14, 11, 59),
      );

      final rows = await repository.getAllWithNames();

      expect(rows, hasLength(2));
      expect(rows.first.operatorName, 'Βαρβάρα');
      expect(
        rows.last.operatorName,
        isNull,
        reason: greekExpectMsg(
          'Συνεδρία χωρίς προφίλ κρατά ακόμη το αρχείο — δεν εξαφανίζεται',
        ),
      );
    });

    test('η παράδοση αφήνει τη γραμμή αλλά της παίρνει τον κάτοχο', () async {
      // Κανονικό κλείσιμο: το ίχνος παύει να μετράει ως παρουσία αμέσως,
      // αντί να παλιώνει μόνο του επί τρία λεπτά.
      await repository.touch(
        operatorId: 1,
        station: 'PICINIO',
        instance: r'C:pp.exe',
        at: DateTime(2026, 9, 14, 12),
      );
      await repository.touch(
        operatorId: 2,
        station: 'TEP-02',
        instance: r'C:\other.exe',
        at: DateTime(2026, 9, 14, 12),
      );

      await repository.release(instance: r'C:pp.exe');

      final all = await repository.getAll();
      expect(
        all,
        hasLength(2),
        reason: greekExpectMsg(
          'Η γραμμή μένει ως ιστορικό «πότε ήταν τελευταία φορά εδώ»',
        ),
      );
      final mine = all.firstWhere((m) => m.operatorId == 1);
      final other = all.firstWhere((m) => m.operatorId == 2);
      expect(mine.instance, isNull);
      expect(mine.isOnlineAt(DateTime(2026, 9, 14, 12)), isFalse);
      expect(
        other.isOnlineAt(DateTime(2026, 9, 14, 12)),
        isTrue,
        reason: greekExpectMsg('Η παράδοση αφορά ΜΟΝΟ το δικό μου αντίγραφο'),
      );
    });
  });
}
