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
    tempDir = await Directory.systemTemp.createTemp('lamp-info-cleanup-');
    dbPath = p.join(tempDir.path, 'lamp.sqlite');
    repository = OldEquipmentRepository();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      for (final type in <String>[
        'missing_sheet',
        'missing_sheet',
        'missing_sheet',
        'duplicate_code_discarded',
      ]) {
        await db.insert('data_issues', <String, Object?>{
          'sheet': 'equipment',
          'issue_type': type,
          'raw_value': 'x',
          'message': 'Πληροφοριακή εγγραφή δοκιμής.',
          'created_at': '2026-01-01T00:00:00',
        });
      }
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

  Future<int> countByType(String type) async {
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM data_issues WHERE issue_type = ?',
        <Object?>[type],
      );
      return rows.first['count'] as int;
    } finally {
      await db.close();
    }
  }

  group('deleteDataIssuesByType', () {
    test('διαγράφει ΜΟΝΟ τον ζητούμενο τύπο και επιστρέφει το πλήθος',
        () async {
      final deleted = await repository.deleteDataIssuesByType(
        dbPath,
        'missing_sheet',
      );

      expect(deleted, 3);
      expect(await countByType('missing_sheet'), 0);
      expect(
        await countByType('duplicate_code_discarded'),
        1,
        reason: 'Οι άλλες ομάδες δεν πρέπει να αγγίζονται.',
      );
    });

    test('επιστρέφει 0 για τύπο χωρίς εγγραφές', () async {
      final deleted = await repository.deleteDataIssuesByType(
        dbPath,
        'xls_conversion_failed',
      );
      expect(deleted, 0);
    });

    test('κενή διαδρομή βάσης πετά σφάλμα', () async {
      expect(
        () => repository.deleteDataIssuesByType('', 'missing_sheet'),
        throwsStateError,
      );
    });
  });
}
