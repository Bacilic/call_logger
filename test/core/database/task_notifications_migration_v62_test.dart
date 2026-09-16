// Η αναβάθμιση v62 φτιάχνει την ουρά ειδοποιήσεων.
//
// Δύο πράγματα κρίνονται εδώ: ότι ο πίνακας μπαίνει σε βάση που δεν τον είχε,
// και ότι ΚΑΜΙΑ υπάρχουσα εκκρεμότητα δεν γεννά αναδρομικά ειδοποίηση — η
// ουρά γεννιέται άδεια, αλλιώς ο πρώτος που θα άνοιγε την εφαρμογή θα έβλεπε
// κάθε ανάθεση που έγινε ποτέ.
//
//   flutter test test/core/database/task_notifications_migration_v62_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Αναβάθμιση v62 — ουρά ειδοποιήσεων', () {
    late Database db;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await db.execute('''
        CREATE TABLE tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          status TEXT,
          assigned_operator_id INTEGER
        )
      ''');
      await db.insert('tasks', {
        'title': 'Ανατέθηκε πριν υπάρξει η ουρά',
        'status': 'open',
        'assigned_operator_id': 22,
      });
    });

    tearDown(() async {
      await db.close();
    });

    Future<Set<String>> tables() async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      return rows.map((r) => r['name'] as String).toSet();
    }

    test('ο πίνακας μπαίνει σε βάση που δεν τον είχε', () async {
      expect(await tables(), isNot(contains('task_notifications')));

      await migrateDatabaseToV62(db);

      expect(await tables(), contains('task_notifications'));
    });

    test('η ουρά γεννιέται άδεια', () async {
      await migrateDatabaseToV62(db);

      expect(await db.query('task_notifications'), isEmpty);
    });

    test('ξανατρέχει χωρίς παρενέργειες', () async {
      await migrateDatabaseToV62(db);
      await db.insert('task_notifications', {
        'recipient_operator_id': 22,
        'task_id': 1,
        'kind': 'assigned',
        'actor_operator_id': 11,
        'created_at': '2026-09-16T10:00:00.000',
      });

      await migrateDatabaseToV62(db);

      expect(await db.query('task_notifications'), hasLength(1));
    });
  });
}
