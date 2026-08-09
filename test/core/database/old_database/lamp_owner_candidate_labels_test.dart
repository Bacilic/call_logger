// Ετικέτες υποψηφίων υπαλλήλων στον οδηγό χειροκίνητης επίλυσης.
//
// Σενάριο 08/08: εξοπλισμός 5010, πεδίο «υπάλληλος», αρχική τιμή
// «Παπαβασιλείου». Δύο υποψήφιοι με το ίδιο επώνυμο — χωρίς το γραφείο τους
// ο χρήστης δεν έχει κανένα κριτήριο επιλογής.
//
// Το τεστ τρέχει τον ΑΝΑΛΥΤΗ, όχι το widget: η πρώτη προσπάθεια διόρθωσης
// άλλαξε λάθος μονοπάτι (τον χάρτη ετικετών που τροφοδοτεί τα «Στοιχεία
// εγγραφής») και το widget συνέχιζε να δείχνει σκέτα ονόματα.
//
//   flutter test test/core/database/old_database/lamp_owner_candidate_labels_test.dart

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
    tempDir = await Directory.systemTemp.createTemp('lamp-owner-labels-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final matching = LampIssueMatchingEngine();
    analyzer = LampIssueFkAnalyzer(
      matching,
      LampIssueResolutionSupport(matching),
    );
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    // Στα Windows το αρχείο μένει κλειδωμένο για λίγο μετά το close· η
    // αποτυχία καθαρισμού δεν πρέπει να κρύβει το πραγματικό αποτέλεσμα.
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  /// Δύο «Παπαβασιλείου» σε διαφορετικά γραφεία· η 340 δεν έχει εξοπλισμό.
  Future<Database> seed() async {
    final db = await openDatabase(dbPath, singleInstance: false);
    await createOldDatabaseSchema(db);
    await db.insert('offices', <String, Object?>{
      'office': 7,
      'office_name': 'Αλλαγή ΜΤΝ',
      'department_name': 'Προϊσταμένη ΜΤΝ',
    });
    await db.insert('offices', <String, Object?>{
      'office': 8,
      'office_name': 'Διευθυντής Παιδιατρικής',
      'department_name': 'Παιδιατρική Κλινική',
    });
    await db.insert('owners', <String, Object?>{
      'owner': 191,
      'last_name': 'Παπαβασιλείου',
      'first_name': 'Τζένη',
      'office': 7,
    });
    await db.insert('owners', <String, Object?>{
      'owner': 340,
      'last_name': 'Παπαβασιλείου',
      'first_name': 'Ελένη',
      'office': 8,
    });
    // Ο 191 έχει εξοπλισμό, η 340 όχι.
    await db.insert('equipment', <String, Object?>{
      'code': 3914,
      'description': 'Ενσύρματο ποντίκι',
      'owner': 191,
    });
    await db.insert('equipment', <String, Object?>{
      'code': 5010,
      'description': 'Lenovo Ποντίκι ενσύρματο',
      'owner_original_text': 'Παπαβασιλείου',
    });
    await db.insert('data_issues', <String, Object?>{
      'issue_type': 'non_numeric_fk',
      'sheet': 'integrity_scan',
      'row_number': 5010,
      'column_name': 'owner',
      'raw_value': 'Παπαβασιλείου',
      'status': 'open',
      'created_at': '2026-08-08T10:00:00.000',
    });
    return db;
  }

  test('οι υποψήφιοι δείχνουν το γραφείο τους', () async {
    final db = await seed();
    try {
      final proposals = await analyzer.analyzeFkIssues(
        db,
        LampIssueType.nonNumericFk,
      );

      final labels = proposals.single.options
          .map((o) => o.label)
          .toList(growable: false);

      expect(
        labels,
        containsAll(<String>[
          '191 · Παπαβασιλείου Τζένη · γραφείο=Αλλαγή ΜΤΝ',
          '340 · Παπαβασιλείου Ελένη · γραφείο=Διευθυντής Παιδιατρικής',
        ]),
        reason: greekExpectMsg(
          'Δύο συνώνυμοι υποψήφιοι χωρίς γραφείο είναι αδιάκριτοι — ο χρήστης '
          'διαλέγει στα τυφλά',
        ),
      );
    } finally {
      await db.close();
    }
  });

  test('ο ασύνδετος υποψήφιος σημαίνεται· ο συνδεδεμένος όχι', () async {
    final db = await seed();
    try {
      final proposals = await analyzer.analyzeFkIssues(
        db,
        LampIssueType.nonNumericFk,
      );
      final options = proposals.single.options;

      final linked = options.firstWhere((o) => o.proposedId == 191);
      final unlinked = options.firstWhere((o) => o.proposedId == 340);

      expect(linked.metadata[kLampOptionUnlinkedFlag], isNull);
      expect(
        unlinked.metadata[kLampOptionUnlinkedFlag],
        isTrue,
        reason: greekExpectMsg(
          'Υποψήφιος που δεν τον χρησιμοποιεί κανένας εξοπλισμός συνήθως '
          'απορρίπτεται — η ένδειξη γλιτώνει τον χρήστη από το να το '
          'ανακαλύψει αφού διαλέξει',
        ),
      );
    } finally {
      await db.close();
    }
  });
}
