// Τα φίλτρα του Ιστορικού δεν επιτρέπεται να ταξινομούν στο χέρι.
//
// Η οθόνη φιλτράρει κατά είδος ή ενέργεια και ΠΑΝΤΑ ταξινομεί κατά χρόνο. Αν
// το ευρετήριο πιάνει μόνο τη στήλη του φίλτρου, η βάση βρίσκει μεν γρήγορα
// τις γραμμές αλλά μετά φτιάχνει προσωρινό δέντρο για τη σειρά — μετρημένο σε
// 200.000 γραμμές, 249 ms αντί για 0,3 ms σε κάθε αλλαγή φίλτρου.
//
// Το τεστ δεν μετρά χρόνο (θα ήταν εύθραυστο): ελέγχει το ίδιο το σχέδιο
// εκτέλεσης που δίνει η βάση. Το «USE TEMP B-TREE FOR ORDER BY» είναι η
// υπογραφή της χειροκίνητης ταξινόμησης.
//
//   flutter test test/core/database/audit_filter_index_test.dart

import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  /// Το σχέδιο εκτέλεσης ενός ερωτήματος, σε μία γραμμή.
  Future<String> planOf(String sql) async {
    final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql');
    return rows.map((r) => r.values.last).join(' | ');
  }

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await applyDatabaseV1Schema(db);

    // Αρκετές γραμμές ώστε ο επιλογέας να μη θεωρήσει ότι η σάρωση είναι
    // φθηνότερη από το ευρετήριο.
    final batch = db.batch();
    for (var i = 0; i < 3000; i++) {
      batch.insert('audit_log', {
        'action': i % 3 == 0 ? 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ' : 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
        'entity_type': i % 3 == 0 ? 'call' : 'department',
        'entity_id': i % 200,
        'timestamp': DateTime(
          2026,
          1,
          1,
        ).add(Duration(minutes: i)).toIso8601String(),
        'user_performing': 'Βασίλης',
      });
    }
    await batch.commit(noResult: true);
    // Ό,τι κάνει και η μετάπτωση: χωρίς στατιστικά ο επιλογέας μαντεύει.
    await db.execute('ANALYZE');
  });

  tearDown(() async => db.close());

  group('τα φίλτρα παίρνουν τη σειρά από το ευρετήριο', () {
    test('φίλτρο είδους δεν ταξινομεί στο χέρι', () async {
      final plan = await planOf(
        "SELECT * FROM audit_log WHERE entity_type = 'call' "
        'ORDER BY timestamp DESC, id DESC LIMIT 50',
      );

      expect(
        plan,
        isNot(contains('TEMP B-TREE')),
        reason: 'Το ευρετήριο οφείλει να δίνει και τη χρονική σειρά: $plan',
      );
      expect(plan, contains('idx_audit_log_entity_type_timestamp'));
    });

    test('φίλτρο ενέργειας δεν ταξινομεί στο χέρι', () async {
      final plan = await planOf(
        "SELECT * FROM audit_log WHERE action = 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ' "
        'ORDER BY timestamp DESC, id DESC LIMIT 50',
      );

      expect(plan, isNot(contains('TEMP B-TREE')), reason: plan);
      expect(plan, contains('idx_audit_log_action_timestamp'));
    });

    test('χωρίς φίλτρο, η σειρά έρχεται από το χρονικό ευρετήριο', () async {
      final plan = await planOf(
        'SELECT * FROM audit_log ORDER BY timestamp DESC, id DESC LIMIT 50',
      );
      expect(plan, isNot(contains('TEMP B-TREE')), reason: plan);
    });
  });

  group('το ερώτημα που κινδύνεψε', () {
    // Δύο ευρετήρια ξεκινούν πλέον από `entity_type`. Χωρίς στατιστικά το
    // SQLite διάλεγε το λάθος για το «ιστορικό αυτής της καρτέλας» —
    // μετρημένο, 4 ms γίνονταν 138 ms. Η μετάπτωση τρέχει ANALYZE ακριβώς
    // γι' αυτό, και αυτό εδώ φυλάει ότι η επιλογή έμεινε σωστή.
    test('το ιστορικό μιας καρτέλας κρατά το δικό του ευρετήριο', () async {
      final plan = await planOf(
        "SELECT * FROM audit_log WHERE entity_type = 'department' "
        'AND entity_id = 42 ORDER BY timestamp DESC',
      );

      expect(
        plan,
        contains('idx_audit_log_entity_type_entity_id'),
        reason:
            'Όταν υπάρχει entity_id, το ζεύγος (entity_type, entity_id) είναι '
            'ασύγκριτα πιο επιλεκτικό από το (entity_type, timestamp): $plan',
      );
    });
  });

  group('τα ευρετήρια του σχήματος', () {
    Future<Set<String>> auditIndexes() async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND tbl_name = 'audit_log' AND name IS NOT NULL",
      );
      return rows.map((r) => r['name'] as String).toSet();
    }

    test('υπάρχουν τα τρία που χρειάζονται, και μόνο αυτά', () async {
      expect(await auditIndexes(), {
        'idx_audit_log_timestamp',
        'idx_audit_log_action_timestamp',
        'idx_audit_log_entity_type_timestamp',
        'idx_audit_log_entity_type_entity_id',
      });
    });

    test('το παλιό ευρετήριο μόνο-ενέργειας δεν ξαναγεννιέται', () async {
      // Καλύπτεται πλήρως από το (action, timestamp), που ξεκινά από την ίδια
      // στήλη. Δύο ευρετήρια για την ίδια δουλειά κοστίζουν χώρο χωρίς κέρδος.
      expect(await auditIndexes(), isNot(contains('idx_audit_log_action')));
    });

    test(
      'ο χρήστης ΔΕΝ πήρε ευρετήριο — μετρήθηκε ότι δεν το χρειάζεται',
      () async {
        // Το φίλτρο χρήστη ήταν ήδη 0,3 ms στις 200.000 γραμμές: με λίγες
        // διακριτές τιμές, η σάρωση του χρονικού ευρετηρίου βρίσκει τις πρώτες
        // 50 αμέσως. Ένα ακόμη ευρετήριο θα κόστιζε 9 MB για μηδέν κέρδος.
        final plan = await planOf(
          "SELECT * FROM audit_log WHERE user_performing = 'Βασίλης' "
          'ORDER BY timestamp DESC, id DESC LIMIT 50',
        );
        expect(plan, isNot(contains('TEMP B-TREE')), reason: plan);
      },
    );
  });
}
