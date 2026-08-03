// Σελιδοποίηση προεπισκόπησης πίνακα: πλήθος εγγραφών + σελίδες χωρίς κενά/διπλότυπα.
//
//   flutter test test/core/database/database_table_inspection_pagination_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    initSqfliteFfiForTests();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    tempDir = await Directory.systemTemp.createTemp('db_preview_paging_test_');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Σελιδοποίηση προεπισκόπησης πίνακα', () {
    test('getTableRowCount επιστρέφει το πραγματικό πλήθος εγγραφών', () async {
      final dbPath = '${tempDir.path}/row_count.db';
      await DatabaseHelper.bindTestDatabaseFile(dbPath);
      final db = await DatabaseHelper.instance.initializeDatabase();

      final batch = db.batch();
      for (var i = 0; i < 620; i++) {
        batch.insert('audit_log', {
          'action': 'ΔΟΚΙΜΗ',
          'timestamp': '2026-08-02T00:00:00',
          'details': 'εγγραφή $i',
        });
      }
      await batch.commit(noResult: true);

      final count = await DatabaseHelper.instance.tableInspection
          .getTableRowCount('audit_log');

      expect(count, 620);
    });

    test(
      'οι σελίδες με offset καλύπτουν ΟΛΕΣ τις εγγραφές χωρίς κενά ή διπλότυπα',
      () async {
        final dbPath = '${tempDir.path}/paging.db';
        await DatabaseHelper.bindTestDatabaseFile(dbPath);
        final db = await DatabaseHelper.instance.initializeDatabase();

        // 1.150 εγγραφές: πάνω από δύο σελίδες των 500.
        final batch = db.batch();
        for (var i = 0; i < 1150; i++) {
          batch.insert('audit_log', {
            'action': 'ΔΟΚΙΜΗ',
            'timestamp': '2026-08-02T00:00:00',
            'details': 'εγγραφή $i',
          });
        }
        await batch.commit(noResult: true);

        final inspection = DatabaseHelper.instance.tableInspection;
        final seenIds = <int>{};
        var offset = 0;
        while (true) {
          final page = await inspection.getTablePreview(
            'audit_log',
            offset: offset,
          );
          if (page.rows.isEmpty) break;
          expect(page.rows.length, lessThanOrEqualTo(500));
          for (final row in page.rows) {
            final id = row['id'] as int;
            expect(
              seenIds.contains(id),
              isFalse,
              reason: 'Διπλότυπη εγγραφή id=$id μεταξύ σελίδων',
            );
            seenIds.add(id);
          }
          offset += page.rows.length;
        }

        expect(seenIds.length, 1150);
      },
    );

    test('η πρώτη σελίδα παραμένει με προεπιλεγμένο όριο 500', () async {
      final dbPath = '${tempDir.path}/first_page.db';
      await DatabaseHelper.bindTestDatabaseFile(dbPath);
      final db = await DatabaseHelper.instance.initializeDatabase();

      final batch = db.batch();
      for (var i = 0; i < 510; i++) {
        batch.insert('audit_log', {
          'action': 'ΔΟΚΙΜΗ',
          'timestamp': '2026-08-02T00:00:00',
          'details': 'εγγραφή $i',
        });
      }
      await batch.commit(noResult: true);

      final page = await DatabaseHelper.instance.tableInspection
          .getTablePreview('audit_log');

      expect(page.rows, hasLength(500));
      expect(page.columns, contains('action'));
    });
  });
}
