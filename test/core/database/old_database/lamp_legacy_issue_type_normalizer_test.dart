// Κανονικοποίηση παλαιών issue_type στο data_issues της Λάμπας.
//
//   flutter test test/core/database/old_database/lamp_legacy_issue_type_normalizer_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_legacy_issue_type_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-legacy-issue-');
    dbPath = p.join(tempDir.path, 'lamp.sqlite');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.execute('''
        CREATE TABLE data_issues (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sheet TEXT,
          row_number INTEGER,
          column_name TEXT,
          raw_value TEXT,
          issue_type TEXT NOT NULL,
          message TEXT,
          created_at TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'open'
        )
      ''');
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Database> openDb() => openDatabase(dbPath, singleInstance: false);

  test(
    'unmatched_office → non_numeric_fk/office· row_number/raw_value/message ανέπαφα',
    () async {
      final db = await openDb();
      try {
        await db.insert('data_issues', <String, Object?>{
          'sheet': 'equipment',
          'row_number': 126,
          'column_name': 'office_original_text',
          'raw_value': 'ΤΕΠ γραμματια',
          'issue_type': 'unmatched_office',
          'message': 'Παλιό μήνυμα ETL για το γραφείο.',
          'created_at': '2023-05-01T00:00:00',
        });

        final changed = await normalizeLegacyDataIssueTypes(db);
        expect(changed, 1);

        final rows = await db.query('data_issues');
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row['issue_type'], 'non_numeric_fk');
        expect(row['column_name'], 'office');
        expect(row['row_number'], 126);
        expect(row['raw_value'], 'ΤΕΠ γραμματια');
        expect(row['message'], 'Παλιό μήνυμα ETL για το γραφείο.');
      } finally {
        await db.close();
      }
    },
  );

  test('δεύτερη εκτέλεση επιστρέφει μηδέν αλλαγές (idempotent)', () async {
    final db = await openDb();
    try {
      await db.insert('data_issues', <String, Object?>{
        'sheet': 'equipment',
        'row_number': 126,
        'column_name': 'office_original_text',
        'raw_value': 'ΤΕΠ γραμματια',
        'issue_type': 'unmatched_office',
        'message': 'msg',
        'created_at': '2023-05-01T00:00:00',
      });

      expect(await normalizeLegacyDataIssueTypes(db), 1);
      expect(await normalizeLegacyDataIssueTypes(db), 0);
    } finally {
      await db.close();
    }
  });

  test('γνωστοί τύποι μένουν ανέγγιχτοι', () async {
    final db = await openDb();
    try {
      await db.insert('data_issues', <String, Object?>{
        'sheet': 'equipment',
        'row_number': 10,
        'column_name': 'office',
        'raw_value': '42',
        'issue_type': 'non_numeric_fk',
        'message': 'ήδη σωστό',
        'created_at': '2026-01-01T00:00:00',
      });
      await db.insert('data_issues', <String, Object?>{
        'sheet': 'network',
        'row_number': 11,
        'column_name': 'ip_address',
        'raw_value': 'not-an-ip',
        'issue_type': 'network_invalid_ip',
        'message': 'IP',
        'created_at': '2026-01-01T00:00:00',
      });

      expect(await normalizeLegacyDataIssueTypes(db), 0);

      final rows = await db.query('data_issues', orderBy: 'row_number ASC');
      expect(rows[0]['issue_type'], 'non_numeric_fk');
      expect(rows[0]['column_name'], 'office');
      expect(rows[1]['issue_type'], 'network_invalid_ip');
      expect(rows[1]['column_name'], 'ip_address');
    } finally {
      await db.close();
    }
  });
}
