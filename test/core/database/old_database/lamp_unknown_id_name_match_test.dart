// Αριθμητική τιμή που είναι ΟΝΟΜΑ εγγραφής, όχι αναγνωριστικό.
//
// Σενάριο 09/08: εξοπλισμός 5002, πεδίο «συμβόλαιο», ωμή τιμή «30236». Η
// σύμβαση υπάρχει — id 231, όνομα «30236 18/12/2024», προμηθευτής MULTILAB AE,
// με τρεις εξοπλισμούς ήδη πάνω της. Ο οδηγός δεν την πρότεινε ποτέ: έψαχνε
// το «30236» μόνο ως αναγνωριστικό και βαθμολογούσε υποψηφίους από
// συμφραζόμενα («χρησιμοποιείται στο ίδιο γραφείο»), οπότε ο χρήστης θα
// δημιουργούσε διπλοεγγραφή.
//
//   flutter test test/core/database/old_database/lamp_unknown_id_name_match_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_fk_analyzer.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_matching_engine.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_models.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_support.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_reporter.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late LampIssueFkAnalyzer analyzer;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-unknown-name-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final matching = LampIssueMatchingEngine();
    analyzer = LampIssueFkAnalyzer(
      matching,
      LampIssueResolutionSupport(matching),
    );
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<Database> seed() async {
    final db = await openDatabase(dbPath, singleInstance: false);
    await createOldDatabaseSchema(db);
    await db.insert('offices', <String, Object?>{
      'office': 50,
      'office_name': 'Computer Room',
      'department_name': 'Πληροφορικής',
    });
    // Η σύμβαση που ψάχνει ο χρήστης — το όνομά της ΞΕΚΙΝΑ με την ωμή τιμή.
    await db.insert('contracts', <String, Object?>{
      'contract': 231,
      'contract_name': '30236 18/12/2024',
      'supplier': 42,
      'supplier_name': 'MULTILAB AE',
      'category': 1,
      'category_name': 'Προμήθεια',
    });
    // Δύο ακόμη, με εξοπλισμό στο ίδιο γραφείο: αυτές πρότεινε ο οδηγός.
    await db.insert('contracts', <String, Object?>{
      'contract': 22,
      'contract_name': '8006/8-6-2004',
      'supplier_name': 'Infotechnica SA',
      'category_name': 'Προμήθεια',
    });
    await db.insert('contracts', <String, Object?>{
      'contract': 23,
      'contract_name': '-',
      'supplier_name': 'RISE COMPUTER CENTER',
      'category_name': 'Προμήθεια',
    });
    await db.insert('offices', <String, Object?>{
      'office': 88,
      'office_name': 'Αιμοδοσία',
      'department_name': 'Αιμοδοσίας',
    });
    // Οι 22 και 23 έχουν εξοπλισμό στο ΙΔΙΟ γραφείο — μόνο γι' αυτό τις
    // πρότεινε ο οδηγός. Η 231 είναι αλλού, άρα δεν είχε καμία ένδειξη
    // συμφραζομένων και δεν εμφανιζόταν καθόλου.
    for (final entry in <(int, int, int)>[
      (900, 22, 50),
      (901, 23, 50),
      (902, 231, 88),
    ]) {
      await db.insert('equipment', <String, Object?>{
        'code': entry.$1,
        'description': 'Cisco Switch',
        'office': entry.$3,
        'contract': entry.$2,
      });
    }
    return db;
  }

  Future<void> addUnknownIdIssue(Database db, int code, String rawValue) async {
    await db.insert('equipment', <String, Object?>{
      'code': code,
      'description': 'Cisco Switch',
      'office': 50,
      'contract_original_text': rawValue,
    });
    await db.insert('data_issues', <String, Object?>{
      'issue_type': 'unknown_id',
      'sheet': 'integrity_scan',
      'row_number': code,
      'column_name': 'contract',
      'raw_value': rawValue,
      'status': 'open',
      'created_at': '2026-08-09T10:00:00.000',
    });
  }

  test('«30236» βρίσκει τη σύμβαση που ονομάζεται έτσι', () async {
    final db = await seed();
    try {
      await addUnknownIdIssue(db, 5002, '30236');

      final proposal = (await analyzer.analyzeFkIssues(
        db,
        LampIssueType.unknownId,
      )).single;

      expect(
        proposal.options.first.proposedId,
        231,
        reason: greekExpectMsg(
          'Ο οδηγός βαθμολογούσε μόνο συμφραζόμενα και πρότεινε συμβάσεις '
          'του ίδιου γραφείου· η σωστή, που λέγεται ακριβώς έτσι, δεν '
          'εμφανιζόταν καν και ο χρήστης θα έφτιαχνε διπλοεγγραφή',
        ),
      );
      expect(proposal.options.first.description, contains('όνομα'));
    } finally {
      await db.close();
    }
  });

  test('η βεβαιότητα ανεβαίνει όταν το όνομα ταιριάζει', () async {
    final db = await seed();
    try {
      await addUnknownIdIssue(db, 5002, '30236');

      final proposal = (await analyzer.analyzeFkIssues(
        db,
        LampIssueType.unknownId,
      )).single;

      expect(
        proposal.confidence,
        greaterThanOrEqualTo(80),
        reason: greekExpectMsg(
          'Ταύτιση ονόματος είναι πολύ ισχυρότερη ένδειξη από «βρίσκεται '
          'στο ίδιο γραφείο»',
        ),
      );
      expect(proposal.proposedId, 231);
    } finally {
      await db.close();
    }
  });

  test('χωρίς ταύτιση ονόματος οι υποψήφιοι συμφραζομένων μένουν', () async {
    final db = await seed();
    try {
      await addUnknownIdIssue(db, 5003, '99999');

      final proposal = (await analyzer.analyzeFkIssues(
        db,
        LampIssueType.unknownId,
      )).single;

      // Οι υποψήφιοι συμφραζομένων παραμένουν — αλλά κανένας δεν σημαίνεται
      // ως ταύτιση ονόματος, και η βεβαιότητα μένει χαμηλή.
      expect(proposal.options, isNotEmpty);
      expect(
        proposal.options.where((o) => (o.description ?? '').contains('όνομα')),
        isEmpty,
        reason: greekExpectMsg(
          'Το 99999 δεν είναι όνομα καμίας σύμβασης· ψεύτικη ένδειξη '
          'ταύτισης θα έσπρωχνε τον χρήστη σε λάθος σύνδεση',
        ),
      );
      expect(proposal.confidence, lessThan(80));
    } finally {
      await db.close();
    }
  });

  test('η τιμή δεν ταιριάζει σε τυχαίο κομμάτι ονόματος', () async {
    final db = await seed();
    try {
      // Το «236» υπάρχει μέσα στο «30236 18/12/2024» — αλλά δεν είναι το όνομα.
      await addUnknownIdIssue(db, 5004, '236');

      final proposal = (await analyzer.analyzeFkIssues(
        db,
        LampIssueType.unknownId,
      )).single;

      expect(
        proposal.options.isEmpty ? null : proposal.options.first.proposedId,
        isNot(231),
        reason: greekExpectMsg(
          'Ταύτιση σε υποσύμβολο θα έδενε τυχαίους αριθμούς με λάθος '
          'συμβάσεις — η αρχή του ονόματος είναι το κριτήριο',
        ),
      );
    } finally {
      await db.close();
    }
  });
}
