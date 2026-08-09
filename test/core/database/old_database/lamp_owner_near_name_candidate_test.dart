// Υποψήφιοι υπάλληλοι που διαφέρουν σε λίγα γράμματα από την ωμή τιμή.
//
// Σενάριο 08/08: εξοπλισμός 5020, πεδίο «υπάλληλος», ωμή τιμή «Μαλατέστα
// Καλλή». Στη βάση ο ίδιος άνθρωπος είναι «Μαλατέστα Καλή» με 21 εξοπλισμούς,
// αλλά ο οδηγός πρότεινε μόνο δημιουργία νέου υπαλλήλου — δηλαδή διπλοεγγραφή.
//
// Το τεστ τρέχει τον ΑΝΑΛΥΤΗ με πραγματική βάση: η λογική ομοιότητας ελέγχεται
// χωριστά σε lamp_owner_name_similarity_test.dart, εδώ ελέγχεται ότι είναι
// όντως συνδεδεμένη στη διαδρομή που βλέπει ο χρήστης.
//
//   flutter test test/core/database/old_database/lamp_owner_near_name_candidate_test.dart

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
    tempDir = await Directory.systemTemp.createTemp('lamp-owner-near-');
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

  Future<Database> open() async {
    final db = await openDatabase(dbPath, singleInstance: false);
    await createOldDatabaseSchema(db);
    await db.insert('offices', <String, Object?>{
      'office': 7,
      'office_name': 'Γραμματεία ΤΕΙ',
      'department_name': 'Διοικητική-Οικονομική',
    });
    return db;
  }

  Future<void> addIssue(Database db, int code, String rawValue) async {
    await db.insert('equipment', <String, Object?>{
      'code': code,
      'description': 'ΠΟΛΥΜΗΧΑΝΗΜΑ SHARP',
      'owner_original_text': rawValue,
    });
    await db.insert('data_issues', <String, Object?>{
      'issue_type': 'non_numeric_fk',
      'sheet': 'integrity_scan',
      'row_number': code,
      'column_name': 'owner',
      'raw_value': rawValue,
      'status': 'open',
      'created_at': '2026-08-08T10:00:00.000',
    });
  }

  test('προτείνει τη «Μαλατέστα Καλή» για τη «Μαλατέστα Καλλή»', () async {
    final db = await open();
    try {
      await db.insert('owners', <String, Object?>{
        'owner': 31,
        'last_name': 'Μαλατέστα',
        'first_name': 'Καλή',
        'office': 7,
      });
      await db.insert('equipment', <String, Object?>{
        'code': 2182,
        'description': 'BARCODE SCANNER',
        'owner': 31,
      });
      await addIssue(db, 5020, 'Μαλατέστα Καλλή');

      final proposals = await analyzer.analyzeFkIssues(
        db,
        LampIssueType.nonNumericFk,
      );
      final options = proposals.single.options;

      final link = options.where((o) => o.proposedId == 31).toList();
      expect(
        link,
        hasLength(1),
        reason: greekExpectMsg(
          'Ένα «λ» διαφορά έκρυβε τον υπάρχοντα υπάλληλο και ο οδηγός '
          'πρότεινε μόνο δημιουργία νέου — διπλοεγγραφή δίπλα σε εγγραφή '
          'με 21 εξοπλισμούς',
        ),
      );
      expect(link.single.label, contains('Μαλατέστα Καλή'));
      expect(
        link.single.description,
        contains('το μικρό όνομα διαφέρει σε 1 γράμμα'),
        reason: greekExpectMsg(
          'Ο χρήστης πρέπει να δει ΓΙΑΤΙ προτείνεται ο υποψήφιος πριν '
          'αποφασίσει — σκέτο ποσοστό δεν λέει τι άλλαξε',
        ),
      );
    } finally {
      await db.close();
    }
  });

  test('η επιλογή δείχνει πόσους εξοπλισμούς έχει ο υποψήφιος', () async {
    final db = await open();
    try {
      await db.insert('owners', <String, Object?>{
        'owner': 31,
        'last_name': 'Μαλατέστα',
        'first_name': 'Καλή',
        'office': 7,
      });
      for (final code in <int>[2182, 2498, 2499]) {
        await db.insert('equipment', <String, Object?>{
          'code': code,
          'description': 'Εκτυπωτής',
          'owner': 31,
        });
      }
      await addIssue(db, 5020, 'Μαλατέστα Καλλή');

      final proposals = await analyzer.analyzeFkIssues(
        db,
        LampIssueType.nonNumericFk,
      );
      final link = proposals.single.options.firstWhere(
        (o) => o.proposedId == 31,
      );

      expect(
        link.description,
        contains('3 εξοπλισμοί'),
        reason: greekExpectMsg(
          'Το πλήθος εξοπλισμών είναι το κριτήριο που χρησιμοποίησε ο ίδιος '
          'ο χρήστης για να δει ότι ο υποψήφιος είναι ο σωστός',
        ),
      );
    } finally {
      await db.close();
    }
  });

  test('δεν προτείνει άσχετο υπάλληλο με κοινό μικρό όνομα', () async {
    final db = await open();
    try {
      // Ο «Πρόβος Βασίλης» έχει πολλούς εξοπλισμούς και θα έδειχνε πειστική
      // επιλογή· είναι όμως άλλος άνθρωπος από τον «Βασίλη Δρόσο».
      await db.insert('owners', <String, Object?>{
        'owner': 239,
        'last_name': 'Πρόβος',
        'first_name': 'Βασίλης',
        'office': 7,
      });
      for (final code in <int>[100, 101, 102]) {
        await db.insert('equipment', <String, Object?>{
          'code': code,
          'description': 'Οθόνη',
          'owner': 239,
        });
      }
      await addIssue(db, 5021, 'Βασίλης Δρόσος');

      final proposals = await analyzer.analyzeFkIssues(
        db,
        LampIssueType.nonNumericFk,
      );

      expect(
        proposals.single.options.where((o) => o.proposedId == 239),
        isEmpty,
        reason: greekExpectMsg(
          'Δύο γράμματα διαφορά στο επώνυμο σημαίνουν άλλο πρόσωπο· λάθος '
          'σύνδεση χαλάει δεδομένα χειρότερα από μια διπλοεγγραφή',
        ),
      );
    } finally {
      await db.close();
    }
  });

  test('μονολεκτική τιμή που είναι ΜΙΚΡΟ όνομα βρίσκει τον υπάλληλο', () async {
    final db = await open();
    try {
      await db.insert('owners', <String, Object?>{
        'owner': 164,
        'last_name': 'Αναγνωστοπούλου',
        'first_name': 'Θάνια',
        'office': 7,
      });
      await db.insert('equipment', <String, Object?>{
        'code': 900,
        'description': 'Οθόνη',
        'owner': 164,
      });
      await addIssue(db, 5023, 'Θάνια');

      final proposals = await analyzer.analyzeFkIssues(
        db,
        LampIssueType.nonNumericFk,
      );

      expect(
        proposals.single.options.where((o) => o.proposedId == 164),
        hasLength(1),
        reason: greekExpectMsg(
          'Η αναζήτηση κοιτούσε μόνο επώνυμα, οπότε όποιος έγραψε σκέτο το '
          'μικρό όνομα έπαιρνε πρόταση για νέο υπάλληλο',
        ),
      );
    } finally {
      await db.close();
    }
  });

  test('το επώνυμο προηγείται όταν η λέξη είναι και τα δύο', () async {
    final db = await open();
    try {
      // Η λέξη «Μαλατέστα» είναι επώνυμο της μίας και μικρό όνομα της άλλης.
      await db.insert('owners', <String, Object?>{
        'owner': 31,
        'last_name': 'Μαλατέστα',
        'first_name': 'Καλή',
        'office': 7,
      });
      await db.insert('owners', <String, Object?>{
        'owner': 500,
        'last_name': 'Παππά',
        'first_name': 'Μαλατέστα',
        'office': 7,
      });
      await addIssue(db, 5024, 'Μαλατέστα');

      final proposals = await analyzer.analyzeFkIssues(
        db,
        LampIssueType.nonNumericFk,
      );
      final ids = proposals.single.options
          .map((o) => o.proposedId)
          .whereType<int>()
          .toList();

      expect(
        ids.first,
        31,
        reason: greekExpectMsg(
          'Μονολεκτική τιμή είναι πρώτα επώνυμο· το μικρό όνομα είναι η '
          'εφεδρική ανάγνωση και μπαίνει μετά',
        ),
      );
      expect(ids, contains(500));
    } finally {
      await db.close();
    }
  });

  test('η ακριβής ταύτιση δεν χάνεται ούτε διπλασιάζεται', () async {
    final db = await open();
    try {
      await db.insert('owners', <String, Object?>{
        'owner': 31,
        'last_name': 'Μαλατέστα',
        'first_name': 'Καλή',
        'office': 7,
      });
      await addIssue(db, 5022, 'Μαλατέστα Καλή');

      final proposals = await analyzer.analyzeFkIssues(
        db,
        LampIssueType.nonNumericFk,
      );

      expect(
        proposals.single.options.where((o) => o.proposedId == 31),
        hasLength(1),
        reason: greekExpectMsg(
          'Η νέα αναζήτηση κοντινών δεν επιτρέπεται να ξαναπροσθέσει '
          'υποψήφιο που βρήκε ήδη η ακριβής ταύτιση',
        ),
      );
    } finally {
      await db.close();
    }
  });
}
