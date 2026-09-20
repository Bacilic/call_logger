// Ποια εγγραφή του Ιστορικού είναι αναλώσιμη και ποια μαρτυρία.
//
// Η ίδια απόφαση γράφεται δύο φορές — μία σε Dart (για την προεπισκόπηση) και
// μία σε SQL (για τη διαγραφή). Αν αποκλίνουν, ο χειριστής εγκρίνει ένα
// νούμερο και σβήνεται άλλο. Το τελευταίο group εδώ είναι ο φρουρός αυτής της
// συμφωνίας: τρέχει και τις δύο πάνω στα ίδια δεδομένα και απαιτεί ταύτιση.
//
//   flutter test test/core/config/audit_retention_class_test.dart

import 'package:call_logger/core/config/audit_retention_class.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('κατάταξη εγγραφής', () {
    test('δημιουργία υπαλλήλου δεν σβήνεται ποτέ', () {
      expect(
        classifyAuditRow(entityType: 'user', action: 'ΔΗΜΙΟΥΡΓΙΑ ΥΠΑΛΛΗΛΟΥ'),
        AuditRetentionClass.permanent,
      );
    });

    test('διαγραφή τμήματος είναι εξίσου αναντικατάστατη', () {
      // Μόλις σβηστεί η γραμμή, τίποτα δεν θυμάται ότι το τμήμα υπήρξε.
      expect(
        classifyAuditRow(entityType: 'department', action: 'ΔΙΑΓΡΑΦΗ'),
        AuditRetentionClass.permanent,
      );
    });

    test('τροποποίηση τμήματος είναι αναλώσιμη', () {
      // Η σημερινή μορφή του τμήματος ζει στον πίνακά του.
      expect(
        classifyAuditRow(
          entityType: 'department',
          action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ',
        ),
        AuditRetentionClass.operational,
      );
    });

    test('δημιουργία κλήσης είναι ημερήσια κίνηση, όχι μαρτυρία', () {
      // Η ίδια η κλήση έχει δική της ημερομηνία στον πίνακα calls.
      expect(
        classifyAuditRow(entityType: 'call', action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ'),
        AuditRetentionClass.volatile,
      );
    });

    test('δημιουργία εκκρεμότητας επίσης', () {
      expect(
        classifyAuditRow(entityType: 'task', action: 'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ'),
        AuditRetentionClass.volatile,
      );
    });

    test('τα αντίγραφα ασφαλείας είναι ρουτίνα', () {
      expect(
        classifyAuditRow(
          entityType: 'backup',
          action: 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ',
        ),
        AuditRetentionClass.volatile,
      );
    });

    test('η επιδιόρθωση ακεραιότητας μένει, όποιο κι αν είναι το είδος', () {
      // Επέμβαση στα δεδομένα — ακόμη και πάνω σε κλήση.
      expect(
        classifyAuditRow(
          entityType: 'call',
          action: 'ΕΠΙΔΙΟΡΘΩΣΗ ΑΚΕΡΑΙΟΤΗΤΑΣ',
        ),
        AuditRetentionClass.permanent,
      );
      expect(
        classifyAuditRow(
          entityType: 'maintenance',
          action: 'ΕΠΙΔΙΟΡΘΩΣΗ ΑΚΕΡΑΙΟΤΗΤΑΣ',
        ),
        AuditRetentionClass.permanent,
      );
    });

    test('άγνωστο είδος πέφτει στη μεσαία κλάση, όχι στην αναλώσιμη', () {
      // Η ασφαλής άγνοια: ό,τι δεν ξέρουμε δεν το πετάμε πρώτο.
      expect(
        classifyAuditRow(entityType: 'κάτι_νέο', action: 'ΚΑΤΙ'),
        AuditRetentionClass.operational,
      );
    });

    test('κενά πεδία δεν ρίχνουν την κατάταξη', () {
      expect(
        classifyAuditRow(entityType: null, action: null),
        AuditRetentionClass.operational,
      );
    });
  });

  group('η SQL συμφωνεί με τη Dart', () {
    // Δείγμα από τα πραγματικά δεδομένα του νοσοκομείου (μετρημένο 19/09):
    // κάθε συνδυασμός entity_type + action που υπάρχει σήμερα στη βάση.
    const sample = <({String? type, String? action})>[
      (type: 'backup', action: 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΕΠΙΤΥΧΙΑ'),
      (type: 'backup', action: 'ΑΝΤΙΓΡΑΦΟ ΑΣΦΑΛΕΙΑΣ ΑΠΟΤΥΧΙΑ'),
      (type: 'call', action: 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ'),
      (type: 'call', action: 'ΚΑΘΑΡΟ ΚΕΙΜΕΝΟ ΚΛΗΣΗΣ'),
      (type: 'call', action: 'ΚΑΤΑΧΩΡΗΣΗ ΣΤΟ LANSWEEPER'),
      (type: 'call', action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΚΛΗΣΗΣ'),
      (type: 'call', action: 'ΕΞΑΙΡΕΣΗ ΑΠΟ LANSWEEPER'),
      (type: 'department', action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΜΗΜΑΤΟΣ'),
      (type: 'department', action: 'ΔΗΜΙΟΥΡΓΙΑ ΤΜΗΜΑΤΟΣ'),
      (type: 'department', action: 'ΔΙΑΓΡΑΦΗ'),
      (type: 'department', action: 'ΕΠΙΔΙΟΡΘΩΣΗ ΑΚΕΡΑΙΟΤΗΤΑΣ'),
      (type: 'equipment', action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΞΟΠΛΙΣΜΟΥ'),
      (type: 'equipment', action: 'ΔΗΜΙΟΥΡΓΙΑ ΕΞΟΠΛΙΣΜΟΥ'),
      (type: 'equipment', action: 'ΔΙΑΓΡΑΦΗ'),
      (type: 'knowledge', action: 'ΔΗΜΙΟΥΡΓΙΑ ΑΡΘΡΟΥ ΓΝΩΣΗΣ'),
      (type: 'maintenance', action: 'ΕΠΙΔΙΟΡΘΩΣΗ ΑΚΕΡΑΙΟΤΗΤΑΣ'),
      (type: 'operator', action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΧΡΗΣΤΗ'),
      (type: 'operator', action: 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ'),
      (type: 'phone', action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΤΗΛΕΦΩΝΟΥ'),
      (type: 'phone', action: 'ΔΙΑΓΡΑΦΗ'),
      (type: 'task', action: 'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ'),
      (type: 'task', action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΚΚΡΕΜΟΤΗΤΑΣ'),
      (type: 'task', action: 'ΚΛΕΙΣΙΜΟ ΕΚΚΡΕΜΟΤΗΤΑΣ'),
      (type: 'task', action: 'ΔΙΑΓΡΑΦΗ'),
      (type: 'user', action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΥΠΑΛΛΗΛΟΥ'),
      (type: 'user', action: 'ΔΗΜΙΟΥΡΓΙΑ ΥΠΑΛΛΗΛΟΥ'),
      (type: 'user', action: 'συσχέτιση από κλήση'),
      (type: 'user', action: 'ΔΙΑΓΡΑΦΗ'),
      (type: 'user', action: 'ΕΠΙΔΙΟΡΘΩΣΗ ΑΚΕΡΑΙΟΤΗΤΑΣ'),
      (type: null, action: null),
      (type: '', action: ''),
    ];

    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE audit_log (id INTEGER PRIMARY KEY, '
        'action TEXT, entity_type TEXT)',
      );
      for (var i = 0; i < sample.length; i++) {
        await db.insert('audit_log', {
          'id': i + 1,
          'action': sample[i].action,
          'entity_type': sample[i].type,
        });
      }
    });

    tearDown(() async => db.close());

    for (final value in AuditRetentionClass.values) {
      test('ίδιες γραμμές για ${value.name}', () async {
        final expected = <int>[];
        for (var i = 0; i < sample.length; i++) {
          final cls = classifyAuditRow(
            entityType: sample[i].type,
            action: sample[i].action,
          );
          if (cls == value) expected.add(i + 1);
        }

        final clause = auditRetentionClassClause(value);
        final rows = await db.rawQuery(
          'SELECT id FROM audit_log WHERE ${clause.sql} ORDER BY id',
          clause.args,
        );
        final actual = rows.map((r) => r['id'] as int).toList();

        expect(
          actual,
          expected,
          reason:
              'Η SQL και η Dart πρέπει να διαλέγουν ΑΚΡΙΒΩΣ τις ίδιες γραμμές '
              'για την κλάση ${value.name}.',
        );
      });
    }

    test('κάθε γραμμή ανήκει σε ακριβώς μία κλάση', () async {
      final seen = <int, int>{};
      for (final value in AuditRetentionClass.values) {
        final clause = auditRetentionClassClause(value);
        final rows = await db.rawQuery(
          'SELECT id FROM audit_log WHERE ${clause.sql}',
          clause.args,
        );
        for (final r in rows) {
          final id = r['id'] as int;
          seen[id] = (seen[id] ?? 0) + 1;
        }
      }
      expect(seen.length, sample.length, reason: 'καμία γραμμή δεν ξεφεύγει');
      expect(
        seen.values.every((count) => count == 1),
        isTrue,
        reason: 'καμία γραμμή δεν μετριέται δύο φορές',
      );
    });
  });
}
