// Η αναβάθμιση v61 δίνει στην εκκρεμότητα στήλη «ποιος την έκλεισε».
//
// Δύο πράγματα κρίνονται εδώ: ότι η στήλη μπαίνει σε βάση που δεν την είχε,
// και ότι ΚΑΜΙΑ ήδη κλεισμένη εκκρεμότητα δεν αποκτά αυτόματα κλείσαντα — η
// απάντηση για εκείνες ζει στο Ιστορικό, και το να αποδοθούν στον υπεύθυνο θα
// ήταν ακριβώς το λάθος που διορθώνει η προσθήκη.
//
//   flutter test test/core/database/closed_by_operator_migration_v61_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Αναβάθμιση v61 — ποιος έκλεισε την εκκρεμότητα', () {
    late Database db;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      // Ο πίνακας ΟΠΩΣ ΗΤΑΝ πριν την αναβάθμιση — χωρίς τη στήλη.
      await db.execute('''
        CREATE TABLE tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          status TEXT,
          completed_at TEXT,
          created_by_operator_id INTEGER,
          assigned_operator_id INTEGER
        )
      ''');
      await db.insert('tasks', {
        'title': 'Έκλεισε πριν υπάρξει η στήλη',
        'status': 'closed',
        'completed_at': '2026-09-01T10:00:00.000',
        'created_by_operator_id': 11,
        'assigned_operator_id': 22,
      });
    });

    tearDown(() async {
      await db.close();
    });

    Future<Set<String>> columns() async {
      final info = await db.rawQuery('PRAGMA table_info(tasks)');
      return info.map((r) => r['name'] as String).toSet();
    }

    test('η στήλη μπαίνει σε βάση που δεν την είχε', () async {
      expect(await columns(), isNot(contains('closed_by_operator_id')));

      await migrateDatabaseToV61(db);

      expect(await columns(), contains('closed_by_operator_id'));
    });

    test('η ήδη κλεισμένη δεν αποκτά κλείσαντα', () async {
      await migrateDatabaseToV61(db);

      final rows = await db.query('tasks');
      expect(rows.single['closed_by_operator_id'], isNull);
      expect(rows.single['assigned_operator_id'], 22);
    });

    test('ξανατρέχει χωρίς παρενέργειες', () async {
      await migrateDatabaseToV61(db);
      await db.update('tasks', {'closed_by_operator_id': 33}, where: 'id = 1');

      await migrateDatabaseToV61(db);

      final rows = await db.query('tasks');
      expect(rows.single['closed_by_operator_id'], 33);
    });
  });
}
