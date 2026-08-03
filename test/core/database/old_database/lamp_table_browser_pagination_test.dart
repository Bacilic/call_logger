// Σελιδοποίηση προεπισκόπησης πινάκων Λάμπας: σελίδες με offset χωρίς κενά/διπλότυπα.
//
//   flutter test test/core/database/old_database/lamp_table_browser_pagination_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_table_browser_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-preview-paging-');
    dbPath = p.join(tempDir.path, 'lamp.db');
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedRows(int count) async {
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.execute(
        'CREATE TABLE preview_items (id INTEGER PRIMARY KEY, name TEXT)',
      );
      final batch = db.batch();
      for (var i = 0; i < count; i++) {
        batch.insert('preview_items', {'name': 'εγγραφή $i'});
      }
      await batch.commit(noResult: true);
    } finally {
      await db.close();
    }
  }

  test('οι σελίδες με offset καλύπτουν ΟΛΕΣ τις εγγραφές χωρίς κενά ή '
      'διπλότυπα', () async {
    await seedRows(450);
    final api = LampTableBrowserApi.instance;

    expect(await api.getTableRowCount(dbPath, 'preview_items'), 450);

    final seenIds = <int>{};
    var offset = 0;
    while (true) {
      final page = await api.getTablePreview(
        dbPath,
        'preview_items',
        offset: offset,
      );
      if (page.rows.isEmpty) break;
      expect(page.rows.length, lessThanOrEqualTo(200));
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

    expect(seenIds.length, 450);
  });
}
