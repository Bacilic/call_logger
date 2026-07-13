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
      'lamp-set-master-self-ref-',
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

  group('Λάμπα · επίλυση set_master_self_reference', () {
    test(
      'αναλυτής επιστρέφει πρόταση όταν row_number είναι NULL αλλά το message έχει code=',
      () async {
        await _insertEquipment(dbPath, code: 1234, setMaster: null);
        await _insertIssue(
          dbPath,
          issueType: 'set_master_self_reference',
          rawValue: '1234',
          columnName: 'set_master',
          rowNumber: null,
          message:
              'Το set_master δείχνει στον ίδιο εξοπλισμό (code=1234).',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.setMasterSelfReference,
        );

        expect(proposals, hasLength(1));
        expect(proposals.single.row, 1234);
        expect(proposals.single.metadata['code'], 1234);
        expect(proposals.single.metadata['operation'], 'clear_set_master');
      },
    );

    test(
      'clear_set_master είναι idempotent όταν set_master είναι ήδη NULL και αφαιρεί data_issues',
      () async {
        await _insertEquipment(dbPath, code: 1234, setMaster: null);
        final issueId = await _insertIssue(
          dbPath,
          issueType: 'set_master_self_reference',
          rawValue: '1234',
          columnName: 'set_master',
          rowNumber: null,
          message:
              'Το set_master δείχνει στον ίδιο εξοπλισμό (code=1234).',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.setMasterSelfReference,
        );
        expect(proposals, hasLength(1));

        final result = await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(proposal: proposals.single),
          ],
        );

        expect(result.resolved, 1);
        expect(result.unresolved, 0);
        expect(
          await _equipmentSetMaster(dbPath, 1234),
          isNull,
        );
        expect(
          await _countIssues(dbPath, issueType: 'set_master_self_reference'),
          0,
        );
        expect(await _issueExists(dbPath, issueId), isFalse);
      },
    );
  });
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

Future<int> _countIssues(String dbPath, {required String issueType}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM data_issues WHERE issue_type = ?',
      <Object?>[issueType],
    );
    return rows.first['count'] as int;
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
