// Ένα πρόβλημα FK υπάρχει μόνο όσο το FK είναι άλυτο.
//
// Σενάριο 09/08: ο χρήστης όρισε νέους υπαλλήλους στους εξοπλισμούς
// 5035-5054. Οι υπάλληλοι δημιουργήθηκαν, τα equipment.owner συνδέθηκαν —
// και τα ίδια πέντε προβλήματα ξαναεμφανίστηκαν στη λίστα.
//
// Τρεις παραβιάσεις του ίδιου συμβολαίου:
//   Α) η δημιουργία υπαλλήλου δεν καθάριζε το ωμό κείμενο, ενώ η σύνδεση με
//      υπάρχοντα το καθάριζε·
//   Β) ο έλεγχος ακεραιότητας κοιτούσε ΜΟΝΟ το ωμό κείμενο και ποτέ αν το FK
//      είχε ήδη λυθεί, οπότε ξαναέφτιαχνε το πρόβλημα·
//   Γ) λύνοντας ένα πρόβλημα έμεναν τα άλλα του ίδιου εξοπλισμού και στήλης
//      — 20 ορφανά «unknown_id» σε εξοπλισμούς με σωστό κάτοχο.
//
//   flutter test test/core/database/old_database/lamp_resolved_fk_stays_resolved_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_reporter.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-resolved-fk-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('offices', <String, Object?>{
        'office': 20,
        'office_name': 'Πληροφορική',
        'department_name': 'Πληροφορικής',
      });
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> withDb(Future<void> Function(Database db) action) async {
    await LampDatabaseProvider.instance.close();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await action(db);
    } finally {
      await db.close();
    }
  }

  Future<Map<String, Object?>> equipmentRow(int code) async {
    late Map<String, Object?> row;
    await withDb((db) async {
      row = (await db.query(
        'equipment',
        where: 'code = ?',
        whereArgs: <Object?>[code],
      )).single;
    });
    return row;
  }

  Future<List<Map<String, Object?>>> openIssues() async {
    late List<Map<String, Object?>> rows;
    await withDb((db) async {
      rows = await db.query('data_issues', where: "status = 'open'");
    });
    return rows;
  }

  test('Α · η δημιουργία υπαλλήλου καθαρίζει το ωμό κείμενο', () async {
    await withDb((db) async {
      await db.insert('equipment', <String, Object?>{
        'code': 5035,
        'description': 'Dell',
        'office': 20,
        'owner_original_text': 'Νίκος Οικονομόπουλος',
      });
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'non_numeric_fk',
        'sheet': 'integrity_scan',
        'row_number': 5035,
        'column_name': 'owner',
        'raw_value': 'Νίκος Οικονομόπουλος',
        'status': 'open',
        'created_at': '2026-08-09T09:27:08.000',
      });
    });

    final service = LampIssueResolutionService();
    final proposal = (await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.nonNumericFk,
    )).single;
    final createOption = proposal.options.firstWhere(
      (o) => o.metadata['operation'] == 'create_owner_and_update_equipment',
    );
    await service.applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: proposal,
        option: createOption,
      ),
    );

    final row = await equipmentRow(5035);
    expect(row['owner'], isNotNull);
    expect(
      row['owner_original_text'],
      isNull,
      reason: greekExpectMsg(
        'Το ωμό κείμενο είναι το ερώτημα· όταν απαντηθεί πρέπει να φύγει, '
        'αλλιώς ο επόμενος έλεγχος το ξαναδιαβάζει ως πρόβλημα',
      ),
    );
  });

  test('Β · ο έλεγχος δεν βγάζει πρόβλημα σε ήδη λυμένο FK', () async {
    await withDb((db) async {
      await db.insert('owners', <String, Object?>{
        'owner': 2918,
        'last_name': 'Οικονομόπουλος',
        'first_name': 'Νίκος',
        'office': 20,
      });
      // Ο κάτοχος υπάρχει και είναι έγκυρος· το ωμό κείμενο έμεινε ως ιστορικό.
      await db.insert('equipment', <String, Object?>{
        'code': 5035,
        'description': 'Dell',
        'office': 20,
        'owner': 2918,
        'owner_original_text': 'Νίκος Οικονομόπουλος',
      });
    });

    final scan = await OldEquipmentRepository().scanIntegrityIssues(dbPath);

    expect(
      scan.issues.where((i) => i['column_name'] == 'owner'),
      isEmpty,
      reason: greekExpectMsg(
        'Ο εξοπλισμός ΕΧΕΙ έγκυρο κάτοχο· ο έλεγχος κοιτούσε μόνο το ωμό '
        'κείμενο και ξαναέφτιαχνε πρόβλημα που δεν υπάρχει',
      ),
    );
  });

  test('Β · γνήσιο πρόβλημα εξακολουθεί να εντοπίζεται', () async {
    await withDb((db) async {
      await db.insert('equipment', <String, Object?>{
        'code': 5036,
        'description': 'Dell',
        'office': 20,
        'owner_original_text': 'Ιωάννα Κυριαζή',
      });
    });

    final scan = await OldEquipmentRepository().scanIntegrityIssues(dbPath);

    expect(
      scan.issues.where((i) => i['column_name'] == 'owner'),
      hasLength(1),
      reason: greekExpectMsg(
        'Χωρίς κάτοχο το πρόβλημα είναι αληθινό — η διόρθωση δεν επιτρέπεται '
        'να κρύψει και αυτά',
      ),
    );
  });

  test('Δ · τα ήδη λυμένα κλείνουν χωρίς να ρωτηθεί ο χρήστης', () async {
    await withDb((db) async {
      await db.insert('owners', <String, Object?>{
        'owner': 2918,
        'last_name': 'Οικονομόπουλος',
        'first_name': 'Νίκος',
        'office': 20,
      });
      // Ο εξοπλισμός έχει σωστό κάτοχο· το ωμό κείμενο καθαρίστηκε. Έμεινε
      // μόνο η εκκρεμότητα, από παλιότερη σάρωση.
      await db.insert('equipment', <String, Object?>{
        'code': 5035,
        'description': 'Dell',
        'office': 20,
        'owner': 2918,
      });
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'non_numeric_fk',
        'sheet': 'integrity_scan',
        'row_number': 5035,
        'column_name': 'owner',
        'raw_value': 'Νίκος Οικονομόπουλος',
        'status': 'open',
        'created_at': '2026-07-22T00:00:00.000',
      });
    });

    final service = LampIssueResolutionService();
    final proposal = (await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.nonNumericFk,
    )).single;

    expect(
      proposal.proposedAction,
      LampIssueResolutionAction.autoFix,
      reason: greekExpectMsg(
        'Χωρίς αυτό ο χρήστης ξαναπερνά από τριάντα βήματα για προβλήματα '
        'που είχε ήδη λύσει',
      ),
    );
    expect(proposal.options, isEmpty);

    await service.applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(proposal: proposal),
    );

    expect(await openIssues(), isEmpty);
    final row = await equipmentRow(5035);
    expect(
      row['owner'],
      2918,
      reason: greekExpectMsg(
        'Το κλείσιμο εκκρεμότητας δεν επιτρέπεται να πειράξει δεδομένα — '
        'μόνο η εκκρεμότητα ήταν λάθος',
      ),
    );
  });

  test('Γ · λύνοντας ένα πρόβλημα κλείνουν όλα του ίδιου πεδίου', () async {
    await withDb((db) async {
      await db.insert('equipment', <String, Object?>{
        'code': 5040,
        'description': 'Dell',
        'office': 20,
        'owner_original_text': 'Μαρία Κυζιρίδου',
      });
      // Ο ίδιος εξοπλισμός και η ίδια στήλη με δύο τύπους προβλήματος: το ένα
      // από παλιότερη σάρωση, το άλλο από τη σημερινή.
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'unknown_id',
        'sheet': 'integrity_scan',
        'row_number': 5040,
        'column_name': 'owner',
        'raw_value': 'Μαρία Κυζιρίδου',
        'status': 'open',
        'created_at': '2026-07-22T00:00:00.000',
      });
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'non_numeric_fk',
        'sheet': 'integrity_scan',
        'row_number': 5040,
        'column_name': 'owner',
        'raw_value': 'Μαρία Κυζιρίδου',
        'status': 'open',
        'created_at': '2026-08-09T09:27:08.000',
      });
    });

    final service = LampIssueResolutionService();
    final proposal = (await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.nonNumericFk,
    )).single;
    await service.applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: proposal,
        option: proposal.options.firstWhere(
          (o) => o.metadata['operation'] == 'create_owner_and_update_equipment',
        ),
      ),
    );

    expect(
      await openIssues(),
      isEmpty,
      reason: greekExpectMsg(
        'Το FK λύθηκε μία φορά· κάθε ανοιχτό πρόβλημα για το ίδιο πεδίο '
        'αφορά πλέον κάτι που δεν υπάρχει',
      ),
    );
  });
}
