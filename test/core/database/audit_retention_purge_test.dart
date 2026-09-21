// Η εκκαθάριση δεν επιτρέπεται να φάει τη μόνη μαρτυρία.
//
// Οι πίνακες του Καταλόγου δεν κρατούν δική τους υπογραφή: η γραμμή του
// Ιστορικού «ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ» είναι η μοναδική απάντηση στο «ποιος το
// έφτιαξε και πότε». Ό,τι όριο κι αν ορίσει ο χειριστής — ηλικίας ή πλήθους —
// αυτές οι γραμμές μένουν.
//
//   flutter test test/core/database/audit_retention_purge_test.dart

import 'package:call_logger/core/config/audit_retention_class.dart';
import 'package:call_logger/core/database/audit_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late AuditService svc;
  final now = DateTime(2026, 9, 19, 12);

  Future<void> insert({
    required String action,
    required String? entityType,
    required int daysAgo,
    String? searchText = 'κειμενο αναζητησησ',
  }) async {
    await db.insert('audit_log', {
      'action': action,
      'entity_type': entityType,
      'timestamp': now.subtract(Duration(days: daysAgo)).toIso8601String(),
      'user_performing': 'Βασίλης',
      'details': 'λεπτομέρειες',
      'search_text': searchText,
    });
  }

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT, timestamp TEXT, user_performing TEXT, details TEXT,
        entity_type TEXT, entity_id INTEGER, entity_name TEXT,
        search_text TEXT, old_values_json TEXT, new_values_json TEXT)
    ''');
    svc = AuditService(db);

    // Πολύ παλιές μαρτυρίες — δύο χρόνια πίσω.
    await insert(
      action: 'ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ',
      entityType: 'department',
      daysAgo: 730,
    );
    await insert(
      action: 'ΔΗΜΙΟΥΡΓΙΑ ΥΠΑΛΛΗΛΟΥ',
      entityType: 'user',
      daysAgo: 700,
    );
    await insert(action: 'ΔΙΑΓΡΑΦΗ', entityType: 'phone', daysAgo: 690);

    // Παλιά αναλώσιμα.
    for (var i = 0; i < 5; i++) {
      await insert(
        action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
        entityType: 'call',
        daysAgo: 400 + i,
      );
    }
    for (var i = 0; i < 3; i++) {
      await insert(
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
        entityType: 'department',
        daysAgo: 300 + i,
      );
    }

    // Πρόσφατα.
    await insert(action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ', entityType: 'call', daysAgo: 2);
  });

  tearDown(() async => db.close());

  Future<int> countWhere(String where) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM audit_log $where',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  group('διαγραφή ανά κλάση', () {
    test('το όριο των αναλώσιμων δεν αγγίζει τις μαρτυρίες', () async {
      final removed = await svc.deleteOlderThanInClass(
        AuditRetentionClass.volatile,
        now.subtract(const Duration(days: 90)),
      );

      expect(removed, 5, reason: 'μόνο οι πέντε παλιές κλήσεις');
      expect(
        await countWhere("WHERE action LIKE 'ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ%'"),
        1,
        reason: 'η δημιουργία τμήματος δύο ετών μένει',
      );
      expect(await countWhere("WHERE action LIKE 'ΔΗΜΙΟΥΡΓΙΑ ΥΠΑΛΛΗΛΟΥ%'"), 1);
      expect(await countWhere("WHERE entity_type = 'phone'"), 1);
    });

    test('το όριο των καρτελών αγγίζει μόνο τις τροποποιήσεις', () async {
      final removed = await svc.deleteOlderThanInClass(
        AuditRetentionClass.operational,
        now.subtract(const Duration(days: 90)),
      );

      expect(removed, 3);
      expect(await countWhere("WHERE entity_type = 'call'"), 6);
    });

    test('καμία κλάση δεν σβήνει πρόσφατες εγγραφές', () async {
      await svc.deleteOlderThanInClass(
        AuditRetentionClass.volatile,
        now.subtract(const Duration(days: 90)),
      );
      expect(
        await countWhere("WHERE entity_type = 'call'"),
        1,
        reason: 'η χθεσινή κλήση μένει',
      );
    });
  });

  group('όριο πλήθους', () {
    test('δεν σβήνει ποτέ μαρτυρίες, όσο σφιχτό κι αν είναι', () async {
      // «Κράτα 1 γραμμή» — το πιο βίαιο όριο που μπορεί να οριστεί.
      await svc.trimToMaxRows(1);

      expect(
        await countWhere(
          "WHERE action LIKE 'ΔΗΜΙΟΥΡΓΙΑ%' AND entity_type IN ('department','user')",
        ),
        2,
        reason:
            'Το οριζόντιο όριο πλήθους δεν επιτρέπεται να παρακάμψει τη '
            'διαβάθμιση — αλλιώς θα έσβηνε το «ποιος το έφτιαξε».',
      );
      expect(await countWhere("WHERE entity_type = 'phone'"), 1);
    });

    test('κρατά τις νεότερες από τις αναλώσιμες', () async {
      await svc.trimToMaxRows(1);

      final rows = await db.rawQuery(
        "SELECT entity_type, timestamp FROM audit_log "
        "WHERE entity_type = 'call' ORDER BY timestamp DESC",
      );
      expect(rows.length, 1, reason: 'έμεινε μία αναλώσιμη');
      expect(
        rows.first['timestamp'],
        now.subtract(const Duration(days: 2)).toIso8601String(),
        reason: 'και είναι η νεότερη',
      );
    });

    test('όριο μεγαλύτερο από το πλήθος δεν σβήνει τίποτα', () async {
      final before = await countWhere('');
      expect(await svc.trimToMaxRows(1000), 0);
      expect(await countWhere(''), before);
    });
  });

  group('συμπίεση χωρίς απώλεια', () {
    test('πετά κείμενο αλλά ΚΑΜΙΑ γραμμή', () async {
      final before = await countWhere('');

      final touched = await svc.compactSearchTextOlderThan(
        now.subtract(const Duration(days: 180)),
      );

      expect(
        touched,
        11,
        reason: '3 μαρτυρίες + 5 παλιές κλήσεις + 3 τροποποιήσεις',
      );
      expect(await countWhere(''), before, reason: 'καμία διαγραφή');
      expect(
        await countWhere('WHERE search_text IS NULL'),
        11,
        reason: 'μόνο οι παλιές έμειναν χωρίς κείμενο',
      );
    });

    test('αγγίζει και τις μόνιμες — δεν χάνεται τίποτα από αυτές', () async {
      await svc.compactSearchTextOlderThan(
        now.subtract(const Duration(days: 180)),
      );

      final rows = await db.rawQuery(
        "SELECT action, details, entity_type FROM audit_log "
        "WHERE action = 'ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ'",
      );
      expect(rows.length, 1);
      expect(rows.first['details'], 'λεπτομέρειες');
      expect(rows.first['entity_type'], 'department');
    });

    test('είναι idempotent — δεύτερο πέρασμα δεν βρίσκει δουλειά', () async {
      final cutoff = now.subtract(const Duration(days: 180));
      await svc.compactSearchTextOlderThan(cutoff);
      expect(await svc.compactSearchTextOlderThan(cutoff), 0);
    });
  });

  group('μέτρηση για την προεπισκόπηση', () {
    test('το πλήθος ανά κλάση συμφωνεί με το σύνολο', () async {
      final counts = await svc.countByRetentionClass();
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      expect(total, await countWhere(''));
      expect(counts[AuditRetentionClass.permanent], 3);
      expect(counts[AuditRetentionClass.volatile], 6);
      expect(counts[AuditRetentionClass.operational], 3);
    });

    test('η μέτρηση προβλέπει ακριβώς όσα θα σβηστούν', () async {
      final cutoff = now.subtract(const Duration(days: 90));
      final predicted = await svc.countOlderThanInClass(
        AuditRetentionClass.volatile,
        cutoff,
      );
      final actual = await svc.deleteOlderThanInClass(
        AuditRetentionClass.volatile,
        cutoff,
      );
      expect(actual, predicted);
    });
  });
}
