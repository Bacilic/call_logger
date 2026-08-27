// Η αναβάθμιση v56 φέρνει τον πίνακα `servers` σε βάσεις που δεν τον είχαν,
// μαζί με τους δύο γνωστούς διακομιστές — ΧΩΡΙΣ κωδικό, που τον ξέρει μόνο ο
// χρήστης.
//
// Το κρίσιμο σημείο είναι η επαναληψιμότητα: η αναβάθμιση μπορεί να ξανατρέξει
// (άλμα εκδόσεων, δεύτερο άνοιγμα), και το seed δεν πρέπει να ξαναγεμίσει τον
// πίνακα ούτε να αναστήσει γραμμές που ο χρήστης έσβησε.
//
//   flutter test test/core/database/servers_migration_v56_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Αναβάθμιση v56 — πίνακας διακομιστών', () {
    late Database db;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    });

    tearDown(() async {
      await db.close();
    });

    test('δημιουργεί τον πίνακα και τους δύο γνωστούς διακομιστές', () async {
      await migrateDatabaseToV56(db);

      final rows = await db.query('servers', orderBy: 'sort_order ASC');
      expect(rows.length, 2);
      expect(rows[0]['host'], '192.168.13.82');
      expect(rows[1]['host'], '192.168.13.83');
    });

    test('ο κωδικός μένει κενός — δεν εφευρίσκουμε μυστικά', () async {
      await migrateDatabaseToV56(db);

      final rows = await db.query('servers');
      for (final r in rows) {
        expect(r['admin_password'], '');
        expect(r['admin_user'], 'Administrator');
      }
    });

    test('ακριβώς ένας διακομιστής είναι προεπιλεγμένος', () async {
      await migrateDatabaseToV56(db);

      final defaults = await db.query('servers', where: 'is_default = 1');
      expect(defaults.length, 1);
      expect(defaults.single['host'], '192.168.13.82');
    });

    test('δεύτερη εκτέλεση δεν διπλασιάζει τις γραμμές', () async {
      await migrateDatabaseToV56(db);
      await migrateDatabaseToV56(db);

      final rows = await db.query('servers');
      expect(rows.length, 2);
    });

    test('δεν ανασταίνει διακομιστή που έσβησε ο χρήστης', () async {
      await migrateDatabaseToV56(db);
      await db.delete('servers', where: "host = ?", whereArgs: ['192.168.13.83']);

      await migrateDatabaseToV56(db);

      final hosts = (await db.query(
        'servers',
      )).map((r) => r['host']).toList();
      expect(hosts, ['192.168.13.82']);
    });

    test('σε βάση με ήδη καταχωρημένο διακομιστή δεν μπαίνει seed', () async {
      await db.execute(kCreateServersTable);
      await db.insert('servers', {
        'name': 'Δικός μου',
        'host': '10.0.0.5',
        'admin_user': 'Administrator',
        'admin_password': 'μυστικό',
        'is_default': 1,
        'sort_order': 1,
      });

      await migrateDatabaseToV56(db);

      final rows = await db.query('servers');
      expect(rows.length, 1);
      expect(rows.single['host'], '10.0.0.5');
    });
  });
}
