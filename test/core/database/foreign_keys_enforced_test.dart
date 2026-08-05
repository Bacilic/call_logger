// Οι κανόνες σχέσεων (foreign keys) επιβάλλονται πραγματικά.
//
// Συμβόλαιο: «κάθε στήλη-δείκτης με δηλωμένο κανόνα δέχεται μόνο υπαρκτή
// εγγραφή, και η διαγραφή του γονιού τακτοποιεί μόνη της τα παιδιά».
//
//   flutter test test/core/database/foreign_keys_enforced_test.dart

import 'package:call_logger/core/database/database_foreign_keys.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('κανόνες σχέσεων στην ενεργή βάση', () {
    late Database db;

    setUpAll(() async {
      await bindCallLoggerIsolatedTestDatabase();
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insertDepartment(String name) {
      return db.insert('departments', {
        'name': name,
        'name_key': name.toLowerCase(),
        'is_deleted': 0,
      });
    }

    Future<int> insertCall(String issue) {
      return db.insert('calls', {
        'date': '2026-08-04',
        'time': '10:00',
        'issue': issue,
        'status': 'completed',
        'search_index': 'fk test',
        'lansweeper_state': 'unsent',
        'is_deleted': 0,
      });
    }

    test('οι κανόνες είναι ενεργοί σε κάθε άνοιγμα σύνδεσης', () async {
      // Η SQLite τους ξεκινά σβηστούς· αν ξεχαστεί το άναμμα, το σχήμα κουβαλά
      // κανόνες που δεν επιβάλλει κανείς και όλα τα υπόλοιπα τεστ εδώ ψεύδονται.
      expect(await areForeignKeysEnabled(db), isTrue);
    });

    test('η υγιής βάση δεν έχει καμία παραβίαση', () async {
      expect(await foreignKeyViolations(db), isEmpty);
    });

    test('εκκρεμότητα σε ανύπαρκτη κλήση απορρίπτεται', () async {
      await expectLater(
        db.insert('tasks', {
          'title': 'σε ανύπαρκτη κλήση',
          'status': 'open',
          'call_id': 987654,
          'created_at': '2026-08-04T10:00:00.000',
          'updated_at': '2026-08-04T10:00:00.000',
          'is_deleted': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('χρήστης σε ανύπαρκτο τμήμα απορρίπτεται', () async {
      await expectLater(
        db.insert('users', {
          'first_name': 'Ανύπαρκτο',
          'last_name': 'Τμήμα',
          'department_id': 987654,
          'is_deleted': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('εγγραφή Lansweeper σε ανύπαρκτη κλήση απορρίπτεται', () async {
      await expectLater(
        db.insert('call_external_links', {
          'call_id': 987654,
          'external_id': '7001',
          'provider': 'lansweeper',
          'created_at': '2026-08-04T10:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('η οριστική διαγραφή κλήσης παρασύρει το ιστορικό της', () async {
      final callId = await insertCall('cascade-links');
      await db.insert('call_external_links', {
        'call_id': callId,
        'external_id': '7001',
        'provider': 'lansweeper',
        'created_at': '2026-08-04T10:00:00.000',
      });

      await db.delete('calls', where: 'id = ?', whereArgs: [callId]);

      final links = await db.query(
        'call_external_links',
        where: 'call_id = ?',
        whereArgs: [callId],
      );
      expect(links, isEmpty);
    });

    test('η οριστική διαγραφή κλήσης αποσυνδέει τις εκκρεμότητές της', () async {
      final callId = await insertCall('set-null-tasks');
      await db.insert('tasks', {
        'title': 'επιβιώνει',
        'status': 'open',
        'call_id': callId,
        'created_at': '2026-08-04T10:00:00.000',
        'updated_at': '2026-08-04T10:00:00.000',
        'is_deleted': 0,
      });

      await db.delete('calls', where: 'id = ?', whereArgs: [callId]);

      final rows = await db.query(
        'tasks',
        columns: ['call_id'],
        where: 'title = ?',
        whereArgs: ['επιβιώνει'],
      );
      // Η εκκρεμότητα δεν χάνεται μαζί με την κλήση — χάνει μόνο τον δεσμό.
      expect(rows.single['call_id'], isNull);
    });

    test('η διαγραφή τμήματος αποσυνδέει χρήστες αντί να τους σβήνει', () async {
      final deptId = await insertDepartment('Τμήμα Προς Διαγραφή');
      await db.insert('users', {
        'first_name': 'Μένει',
        'last_name': 'Ορφανός',
        'department_id': deptId,
        'is_deleted': 0,
      });

      await db.delete('departments', where: 'id = ?', whereArgs: [deptId]);

      final rows = await db.query(
        'users',
        columns: ['department_id'],
        where: 'first_name = ?',
        whereArgs: ['Μένει'],
      );
      expect(rows.single['department_id'], isNull);
    });

    test('η διαγραφή τμήματος παρασύρει τις συσχετίσεις τηλεφώνων', () async {
      final deptId = await insertDepartment('Τμήμα Με Τηλέφωνο');
      final phoneId = await db.insert('phones', {
        'number': 'fk-9001',
        'is_deleted': 0,
      });
      await db.insert('department_phones', {
        'department_id': deptId,
        'phone_id': phoneId,
      });

      await db.delete('departments', where: 'id = ?', whereArgs: [deptId]);

      final links = await db.query(
        'department_phones',
        where: 'phone_id = ?',
        whereArgs: [phoneId],
      );
      final phones = await db.query(
        'phones',
        where: 'id = ?',
        whereArgs: [phoneId],
      );
      // Η συσχέτιση φεύγει, το τηλέφωνο μένει: δεν είναι παιδί του τμήματος.
      expect(links, isEmpty);
      expect(phones, hasLength(1));
    });

    test('τα ιστορικά στιγμιότυπα της κλήσης μένουν ελεύθερα', () async {
      // Σκόπιμα χωρίς κανόνα: η κλήση κρατά τι ίσχυε τότε, και ένας κανόνας θα
      // πήγαινε πίσω να αλλάξει ιστορικά δεδομένα όταν σβήνεται ο υπάλληλος.
      final callId = await db.insert('calls', {
        'date': '2026-08-04',
        'time': '10:00',
        'caller_id': 987654,
        'equipment_id': 987655,
        'category_id': 987656,
        'caller_text': 'Στιγμιότυπο Καλούντα',
        'status': 'completed',
        'search_index': 'snapshot',
        'lansweeper_state': 'unsent',
        'is_deleted': 0,
      });

      final rows = await db.query(
        'calls',
        columns: ['caller_id'],
        where: 'id = ?',
        whereArgs: [callId],
      );
      expect(rows.single['caller_id'], 987654);
    });
  });
}
