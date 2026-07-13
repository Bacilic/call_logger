import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late OldEquipmentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-issue-deferral-');
    dbPath = p.join(tempDir.path, 'lamp.sqlite');
    repository = OldEquipmentRepository();
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

  group('Λάμπα · αναβολή προβλημάτων ETL', () {
    test('υπάρχουσα βάση χωρίς στήλη status αναβαθμίζεται και μετράει μόνο open', () async {
      final legacyDb = await openDatabase(dbPath, singleInstance: false);
      try {
        await legacyDb.execute('DROP TABLE IF EXISTS data_issues');
        await legacyDb.execute(
          '''
          CREATE TABLE data_issues (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sheet TEXT,
            row_number INTEGER,
            column_name TEXT,
            raw_value TEXT,
            issue_type TEXT NOT NULL,
            message TEXT,
            created_at TEXT NOT NULL
          )
          ''',
        );
        await legacyDb.insert('data_issues', <String, Object?>{
          'sheet': 'integrity_scan',
          'issue_type': 'unknown_id',
          'raw_value': '999',
          'column_name': 'office',
          'row_number': 100,
          'message': 'δοκιμή',
          'created_at': '2026-01-01T00:00:00',
        });
      } finally {
        await legacyDb.close();
      }

      final openIssues = await repository.dataIssues(dbPath);
      expect(openIssues, hasLength(1));
      expect(openIssues.single['status'], kDataIssueStatusOpen);

      final openCount = await repository.dataIssueCount(dbPath);
      expect(openCount, 1);
    });

    test('deferDataIssuesByIds μεταφέρει εγγραφές σε deferred και εξαιρούνται από open', () async {
      final issueId = await _insertIssue(
        dbPath,
        issueType: 'unknown_id',
        rawValue: '42',
        columnName: 'office',
        rowNumber: 200,
      );

      final deferred = await repository.deferDataIssuesByIds(dbPath, <int>[issueId]);
      expect(deferred, 1);

      expect(await repository.dataIssueCount(dbPath), 0);
      final openIssues = await repository.dataIssues(dbPath);
      expect(openIssues, isEmpty);

      final deferredIssues = await repository.deferredDataIssues(dbPath);
      expect(deferredIssues, hasLength(1));
      expect(deferredIssues.single['id'], issueId);
      expect(deferredIssues.single['status'], kDataIssueStatusDeferred);
    });

    test('reopenDeferredDataIssuesByType επαναφέρει σε open', () async {
      final issueId = await _insertIssue(
        dbPath,
        issueType: 'non_numeric_fk',
        rawValue: 'Κείμενο',
        columnName: 'office',
        rowNumber: 300,
      );
      await repository.deferDataIssuesByIds(dbPath, <int>[issueId]);

      final reopened = await repository.reopenDeferredDataIssuesByType(
        dbPath,
        'non_numeric_fk',
      );
      expect(reopened, 1);

      expect(await repository.dataIssueCount(dbPath), 1);
      final deferredIssues = await repository.deferredDataIssues(dbPath);
      expect(deferredIssues, isEmpty);

      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        final row = await db.query(
          'data_issues',
          where: 'id = ?',
          whereArgs: <Object?>[issueId],
        );
        expect(row.single['status'], kDataIssueStatusOpen);
      } finally {
        await db.close();
      }
    });

    test('deferredDataIssues ομαδοποιούνται ανά τύπο', () async {
      await _insertIssue(
        dbPath,
        issueType: 'unknown_id',
        rawValue: '1',
        columnName: 'office',
        rowNumber: 401,
      );
      final deferredId = await _insertIssue(
        dbPath,
        issueType: 'unknown_id',
        rawValue: '2',
        columnName: 'office',
        rowNumber: 402,
      );
      await _insertIssue(
        dbPath,
        issueType: 'duplicate_asset_no',
        rawValue: 'ASSET',
        columnName: 'asset_no',
      );
      final deferredAssetId = await _insertIssue(
        dbPath,
        issueType: 'duplicate_asset_no',
        rawValue: 'ASSET-2',
        columnName: 'asset_no',
      );
      await repository.deferDataIssuesByIds(
        dbPath,
        <int>[deferredId, deferredAssetId],
      );

      final grouped = await repository.deferredDataIssuesGroupedByType(dbPath);
      expect(grouped.keys, containsAll(<String>['unknown_id', 'duplicate_asset_no']));
      expect(grouped['unknown_id'], hasLength(1));
      expect(grouped['duplicate_asset_no'], hasLength(1));
      expect(await repository.dataIssueCount(dbPath), 2);
    });
  });
}

Future<int> _insertIssue(
  String dbPath, {
  required String issueType,
  required String rawValue,
  required String columnName,
  int? rowNumber,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    return await db.insert('data_issues', <String, Object?>{
      'sheet': 'integrity_scan',
      'issue_type': issueType,
      'raw_value': rawValue,
      'column_name': columnName,
      'row_number': rowNumber,
      'message': 'δοκιμαστικό πρόβλημα',
      'created_at': '2026-01-01T00:00:00',
      'status': kDataIssueStatusOpen,
    });
  } finally {
    await db.close();
  }
}
