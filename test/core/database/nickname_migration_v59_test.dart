// Η αναβάθμιση v59 δίνει στους υπαλλήλους στήλη ψευδωνύμου.
//
// Δύο πράγματα κρίνονται εδώ: ότι η στήλη μπαίνει σε βάση που δεν την είχε,
// και ότι ΚΑΜΙΑ υπάρχουσα εγγραφή δεν πειράζεται — η μεταφορά του ψευδωνύμου
// από την παρένθεση του ονόματος είναι απόφαση του χρήστη, μία-μία.
//
//   flutter test test/core/database/nickname_migration_v59_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Αναβάθμιση v59 — ψευδώνυμο υπαλλήλου', () {
    late Database db;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      // Ο πίνακας ΟΠΩΣ ΗΤΑΝ πριν την αναβάθμιση — χωρίς τη στήλη.
      await db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          last_name TEXT NOT NULL,
          first_name TEXT NOT NULL,
          is_deleted INTEGER DEFAULT 0
        )
      ''');
      await db.insert('users', {
        'last_name': 'Παπαγεωργίου',
        'first_name': '(Γωγώ) Γεωργία',
      });
    });

    tearDown(() async {
      await db.close();
    });

    Future<Set<String>> columns() async {
      final info = await db.rawQuery('PRAGMA table_info(users)');
      return info.map((r) => r['name'] as String).toSet();
    }

    test('η στήλη μπαίνει σε βάση που δεν την είχε', () async {
      expect(await columns(), isNot(contains('nickname')));

      await migrateDatabaseToV59(db);

      expect(await columns(), contains('nickname'));
    });

    test('καμία υπάρχουσα εγγραφή δεν μεταφέρεται αυτόματα', () async {
      await migrateDatabaseToV59(db);

      final rows = await db.query('users');
      expect(rows.single['first_name'], '(Γωγώ) Γεωργία');
      expect(rows.single['nickname'], isNull);
    });

    test('ξανατρέχει χωρίς παρενέργειες', () async {
      await migrateDatabaseToV59(db);
      await db.update('users', {'nickname': 'Γωγώ'}, where: 'id = 1');

      await migrateDatabaseToV59(db);

      final rows = await db.query('users');
      expect(rows.single['nickname'], 'Γωγώ');
    });
  });
}
