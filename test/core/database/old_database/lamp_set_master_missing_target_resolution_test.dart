import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late LampIssueResolutionService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'lamp-set-master-missing-',
    );
    dbPath = p.join(tempDir.path, 'lamp.sqlite');
    service = LampIssueResolutionService();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Λάμπα · επίλυση set_master_missing_target', () {
    test(
      'ο αναλυτής παράγει ανεπίλυτη πρόταση με στοιχεία εγγραφής',
      () async {
        await _insertEquipment(dbPath, code: 100, setMaster: 999);
        await _insertIssue(
          dbPath,
          issueType: 'set_master_missing_target',
          rawValue: '999',
          columnName: 'set_master',
          rowNumber: 100,
          message:
              'Το set_master δεν αντιστοιχεί σε υπαρκτό εξοπλισμό για code=100.',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.setMasterMissingTarget,
        );

        expect(proposals, hasLength(1));
        final proposal = proposals.single;
        expect(proposal.row, 100);
        expect(proposal.column, 'set_master');
        expect(proposal.originalValue, '999');
        expect(proposal.proposedAction, LampIssueResolutionAction.unresolved);
        expect(proposal.metadata['rowContextCode'], 100);
        expect(proposal.metadata['rowContextDescription'], 'Εξοπλισμός 100');
      },
    );

    test(
      'ο αναλυτής βρίσκει τον κωδικό από το message όταν λείπει το row_number',
      () async {
        await _insertEquipment(dbPath, code: 100, setMaster: 999);
        await _insertIssue(
          dbPath,
          issueType: 'set_master_missing_target',
          rawValue: '999',
          columnName: 'set_master',
          rowNumber: null,
          message:
              'Το set_master δεν αντιστοιχεί σε υπαρκτό εξοπλισμό για code=100.',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.setMasterMissingTarget,
        );

        expect(proposals, hasLength(1));
        expect(proposals.single.row, 100);
      },
    );

    test(
      'χειροκίνητη σύνδεση με υπαρκτό κωδικό ενημερώνει το set_master '
      'και κλείνει την εγγραφή προβλήματος',
      () async {
        await _insertEquipment(dbPath, code: 100, setMaster: 999);
        await _insertEquipment(dbPath, code: 200, setMaster: null);
        final issueId = await _insertIssue(
          dbPath,
          issueType: 'set_master_missing_target',
          rawValue: '999',
          columnName: 'set_master',
          rowNumber: 100,
          message:
              'Το set_master δεν αντιστοιχεί σε υπαρκτό εξοπλισμό για code=100.',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.setMasterMissingTarget,
        );
        expect(proposals, hasLength(1));

        await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(
              proposal: _withOperation(
                proposals.single,
                LampIssueResolutionOperations.setFieldManual,
              ),
              textInput: '200',
            ),
          ],
        );

        expect(await _equipmentSetMaster(dbPath, 100), 200);
        expect(await _issueExists(dbPath, issueId), isFalse);
      },
    );

    test(
      'η εκκαθάριση πεδίου μηδενίζει το set_master και κλείνει την εγγραφή',
      () async {
        await _insertEquipment(dbPath, code: 100, setMaster: 999);
        final issueId = await _insertIssue(
          dbPath,
          issueType: 'set_master_missing_target',
          rawValue: '999',
          columnName: 'set_master',
          rowNumber: 100,
          message:
              'Το set_master δεν αντιστοιχεί σε υπαρκτό εξοπλισμό για code=100.',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.setMasterMissingTarget,
        );
        expect(proposals, hasLength(1));

        await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(
              proposal: _withOperation(
                proposals.single,
                LampIssueResolutionOperations.clearField,
              ),
            ),
          ],
        );

        expect(await _equipmentSetMaster(dbPath, 100), isNull);
        expect(await _issueExists(dbPath, issueId), isFalse);
      },
    );

    test(
      'χειροκίνητη σύνδεση με ΑΝΥΠΑΡΚΤΟ κωδικό αποτυγχάνει και δεν αλλάζει τίποτα',
      () async {
        await _insertEquipment(dbPath, code: 100, setMaster: 999);
        final issueId = await _insertIssue(
          dbPath,
          issueType: 'set_master_missing_target',
          rawValue: '999',
          columnName: 'set_master',
          rowNumber: 100,
          message:
              'Το set_master δεν αντιστοιχεί σε υπαρκτό εξοπλισμό για code=100.',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.setMasterMissingTarget,
        );

        final result = await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(
              proposal: _withOperation(
                proposals.single,
                LampIssueResolutionOperations.setFieldManual,
              ),
              textInput: '555',
            ),
          ],
        );

        expect(result.errors, isNotEmpty);
        expect(await _equipmentSetMaster(dbPath, 100), 999);
        expect(await _issueExists(dbPath, issueId), isTrue);
      },
    );
  });
}

/// Καθρέφτης του proposalWithOperation του controller για τον οδηγό ανεπίλυτων.
LampIssueResolutionProposal _withOperation(
  LampIssueResolutionProposal proposal,
  String operation,
) {
  return LampIssueResolutionProposal(
    issueType: proposal.issueType,
    issueIds: proposal.issueIds,
    sheet: proposal.sheet,
    row: proposal.row,
    column: proposal.column,
    originalValue: proposal.originalValue,
    proposedAction: proposal.proposedAction,
    proposedId: proposal.proposedId,
    proposedMatch: proposal.proposedMatch,
    confidence: proposal.confidence,
    options: proposal.options,
    notes: proposal.notes,
    metadata: <String, Object?>{
      ...proposal.metadata,
      'operation': operation,
      'fkColumn': proposal.column,
      'code': proposal.row,
    },
  );
}

Future<void> _insertEquipment(
  String dbPath, {
  required int code,
  int? setMaster,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    await db.insert('equipment', <String, Object?>{
      'code': code,
      'description': 'Εξοπλισμός $code',
      'model': 1,
      'set_master': setMaster,
    });
  } finally {
    await db.close();
  }
}

Future<int> _insertIssue(
  String dbPath, {
  required String issueType,
  required String rawValue,
  required String columnName,
  required String message,
  int? rowNumber,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    return await db.insert('data_issues', <String, Object?>{
      'sheet': 'equipment',
      'issue_type': issueType,
      'raw_value': rawValue,
      'column_name': columnName,
      'row_number': rowNumber,
      'message': message,
      'created_at': '2026-01-01T00:00:00',
    });
  } finally {
    await db.close();
  }
}

Future<int?> _equipmentSetMaster(String dbPath, int code) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    final rows = await db.query(
      'equipment',
      columns: <String>['set_master'],
      where: 'code = ?',
      whereArgs: <Object?>[code],
    );
    if (rows.isEmpty) return null;
    return rows.first['set_master'] as int?;
  } finally {
    await db.close();
  }
}

Future<bool> _issueExists(String dbPath, int issueId) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    final rows = await db.query(
      'data_issues',
      where: 'id = ?',
      whereArgs: <Object?>[issueId],
    );
    return rows.isNotEmpty;
  } finally {
    await db.close();
  }
}
