// Τιμές «υπαλλήλου» που στην πραγματικότητα περιγράφουν χώρο.
//
// Σενάριο 08/08: εξοπλισμός 5034, ωμή τιμή «Γιατροί Μαιευτικής». Ο οδηγός
// πρόσφερε μόνο δημιουργία υπαλλήλου με επώνυμο «Γιατροί» ή παράλειψη.
//
// Η λύση δεν είναι η αποσύνδεση — στη Λάμπα κάθε ένας από τους 3.361
// αυθεντικούς εξοπλισμούς έχει ΚΑΙ γραφείο ΚΑΙ υπάλληλο. Είναι ο ρητός
// ορισμός και των δύο, από τον χρήστη, μέσα στο ίδιο βήμα.
//
//   flutter test test/core/database/old_database/lamp_owner_place_value_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_fk_analyzer.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_matching_engine.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
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
    tempDir = await Directory.systemTemp.createTemp('lamp-owner-place-');
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
      'office': 27,
      'office_name': 'Γραφείο Ιατρών Γυναικολογικής',
      'department_name': 'Μαιευτική-Γυναικολογική Κλινική',
    });
    await db.insert('offices', <String, Object?>{
      'office': 182,
      'office_name': 'Διευθυντής Γυναικολογικής',
      'department_name': 'Μαιευτική-Γυναικολογική Κλινική',
    });
    await db.insert('offices', <String, Object?>{
      'office': 43,
      'office_name': 'Γραφείο Υλικού #1',
      'department_name': 'Οικονομικό Τμήμα',
    });
    return db;
  }

  Future<void> addOwnerIssue(
    Database db,
    int code,
    String rawValue, {
    int? office,
    String? officeRawValue,
  }) async {
    await db.insert('equipment', <String, Object?>{
      'code': code,
      'description': 'Epson',
      'owner_original_text': rawValue,
      'office': ?office,
      'office_original_text': ?officeRawValue,
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

  LampIssueResolutionOption placementOption(
    LampIssueResolutionProposal proposal,
  ) => proposal.options.firstWhere((o) => o.requiresPlacementInput);

  group('ο αναλυτής', () {
    test('η αποσύνδεση δεν προσφέρεται πια', () async {
      final db = await open();
      try {
        await addOwnerIssue(db, 5034, 'Γιατροί Μαιευτικής');

        final proposals = await analyzer.analyzeFkIssues(
          db,
          LampIssueType.nonNumericFk,
        );

        expect(
          proposals.single.options.where((o) => o.id == 'owner_null_keep_note'),
          isEmpty,
          reason: greekExpectMsg(
            'Στη Λάμπα κάθε αυθεντικός εξοπλισμός έχει και γραφείο και '
            'υπάλληλο· άδειο πεδίο δεν είναι έγκυρη κατάληξη',
          ),
        );
        expect(
          proposals.single.options.map((o) => o.id),
          contains('owner_null_clear_original'),
          reason: greekExpectMsg(
            'Η εκκαθάριση μένει: για σκέτα σκουπίδια που δεν αξίζει να '
            'μείνουν γραμμένα',
          ),
        );
      } finally {
        await db.close();
      }
    });

    test('ο ορισμός τοποθέτησης μπαίνει πρώτος όταν η τιμή είναι χώρος', () async {
      final db = await open();
      try {
        await addOwnerIssue(db, 5034, 'Γιατροί Μαιευτικής');

        final proposals = await analyzer.analyzeFkIssues(
          db,
          LampIssueType.nonNumericFk,
        );
        final first = proposals.single.options.first;

        expect(first.requiresPlacementInput, isTrue);
        expect(
          first.description,
          contains('Μαιευτική-Γυναικολογική Κλινική'),
          reason: greekExpectMsg(
            'Καμία λέξη δεν ταιριάζει ολόκληρη· η ρίζα «μαιευτ» δίνει στον '
            'χρήστη σημείο εκκίνησης αντί για λευκό πεδίο',
          ),
        );
      } finally {
        await db.close();
      }
    });

    test('με πραγματικό όνομα ο υποψήφιος προηγείται της τοποθέτησης', () async {
      final db = await open();
      try {
        await db.insert('owners', <String, Object?>{
          'owner': 31,
          'last_name': 'Μαλατέστα',
          'first_name': 'Καλή',
          'office': 27,
        });
        await addOwnerIssue(db, 5020, 'Μαλατέστα Καλλή');

        final options = (await analyzer.analyzeFkIssues(
          db,
          LampIssueType.nonNumericFk,
        )).single.options;

        expect(options.first.proposedId, 31);
        expect(
          options.any((o) => o.requiresPlacementInput),
          isTrue,
          reason: greekExpectMsg(
            'Τα πεδία υπάρχουν παντού: όταν ο υποψήφιος είναι λάθος, χωρίς '
            'αυτά δεν μένει άλλη διέξοδος από την παράλειψη',
          ),
        );
      } finally {
        await db.close();
      }
    });
  });

  group('η εφαρμογή', () {
    Future<LampIssueResolutionProposal> seedAndAnalyze({
      required String rawValue,
      String? officeRawValue,
    }) async {
      final db = await open();
      try {
        await addOwnerIssue(db, 5034, rawValue, officeRawValue: officeRawValue);
        await db.insert('data_issues', <String, Object?>{
          'issue_type': 'non_numeric_fk',
          'sheet': 'integrity_scan',
          'row_number': 5034,
          'column_name': 'office',
          'raw_value': officeRawValue ?? rawValue,
          'status': 'open',
          'created_at': '2026-08-08T10:00:00.000',
        });
        await db.insert('owners', <String, Object?>{
          'owner': 81,
          'last_name': 'Καμπάς',
          'first_name': 'Νικόλαος',
          'office': 182,
        });
      } finally {
        await db.close();
      }
      await LampDatabaseProvider.instance.close();
      final proposals = await LampIssueResolutionService().analyzeIssues(
        databasePath: dbPath,
        issueType: LampIssueType.nonNumericFk,
      );
      return proposals.firstWhere((p) => p.column == 'owner');
    }

    Future<Map<String, Object?>> equipmentRow() async {
      await LampDatabaseProvider.instance.close();
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        return (await db.query(
          'equipment',
          where: 'code = ?',
          whereArgs: <Object?>[5034],
        )).single;
      } finally {
        await db.close();
      }
    }

    test('γραφείο και υπάλληλος γράφονται μαζί', () async {
      final proposal = await seedAndAnalyze(
        rawValue: 'Γιατροί Μαιευτικής',
        officeRawValue: 'Γιατροί Μαιευτικής',
      );

      await LampIssueResolutionService().applySingleDecision(
        databasePath: dbPath,
        decision: LampIssueResolutionDecision(
          proposal: proposal,
          option: placementOption(proposal),
          placementInput: const LampPlacementInput(officeId: 27, ownerId: 81),
        ),
      );

      final row = await equipmentRow();
      expect(row['office'], 27);
      expect(row['owner'], 81);
      expect(row['office_original_text'], isNull);
      expect(row['owner_original_text'], isNull);
    });

    test('μόνο γραφείο: το πρόβλημα υπαλλήλου μένει ανοιχτό', () async {
      final proposal = await seedAndAnalyze(rawValue: 'Γιατροί Μαιευτικής');

      final result = await LampIssueResolutionService().applySingleDecision(
        databasePath: dbPath,
        decision: LampIssueResolutionDecision(
          proposal: proposal,
          option: placementOption(proposal),
          placementInput: const LampPlacementInput(officeId: 27),
        ),
      );

      final row = await equipmentRow();
      expect(row['office'], 27);
      expect(row['owner'], isNull);
      expect(
        row['owner_original_text'],
        'Γιατροί Μαιευτικής',
        reason: greekExpectMsg(
          'Μισή σωστή πληροφορία αξίζει περισσότερο από καμία — το κείμενο '
          'μένει για να ξαναδουλευτεί το πρόβλημα αργότερα',
        ),
      );
      expect(result.unresolved, 1);

      await LampDatabaseProvider.instance.close();
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        final open = await db.query(
          'data_issues',
          where: "column_name = 'owner' AND status = 'open'",
        );
        expect(open, hasLength(1));
      } finally {
        await db.close();
      }
    });

    test('το πρόβλημα γραφείου κλείνει μαζί', () async {
      final proposal = await seedAndAnalyze(
        rawValue: 'Γιατροί Μαιευτικής',
        officeRawValue: 'Γιατροί Μαιευτικής',
      );

      await LampIssueResolutionService().applySingleDecision(
        databasePath: dbPath,
        decision: LampIssueResolutionDecision(
          proposal: proposal,
          option: placementOption(proposal),
          placementInput: const LampPlacementInput(officeId: 27, ownerId: 81),
        ),
      );

      await LampDatabaseProvider.instance.close();
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        final remaining = await db.query(
          'data_issues',
          where: 'row_number = 5034',
        );
        expect(
          remaining,
          isEmpty,
          reason: greekExpectMsg(
            'Χωρίς αυτό ο οδηγός θα ξαναρωτούσε για το γραφείο δέκα βήματα '
            'μετά, και η απάντηση εκεί θα αντικαθιστούσε αυτό που μόλις '
            'όρισε ο χρήστης',
          ),
        );
      } finally {
        await db.close();
      }
    });
  });
}
