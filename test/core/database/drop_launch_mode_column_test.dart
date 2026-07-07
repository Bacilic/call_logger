import 'package:call_logger/core/database/database_lexicon_open_normalizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Set<String>> _remoteToolsColumns(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(remote_tools)');
  return info.map((r) => r['name'] as String).toSet();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('dropRemoteToolsLaunchModeColumnOnOpen αφαιρεί launch_mode idempotent',
      () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      singleInstance: false,
    );
    try {
      await db.execute('''
        CREATE TABLE remote_tools (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          role TEXT NOT NULL,
          executable_path TEXT NOT NULL,
          launch_mode TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');
      await db.insert('remote_tools', {
        'name': 'RDP Tool',
        'role': 'rdp',
        'executable_path': r'C:\mstsc.exe',
        'launch_mode': 'template_file',
        'sort_order': 1,
        'is_active': 1,
      });

      await dropRemoteToolsLaunchModeColumnOnOpen(db);

      final columnsAfterFirst = await _remoteToolsColumns(db);
      expect(columnsAfterFirst, isNot(contains('launch_mode')));
      expect(columnsAfterFirst, containsAll(<String>[
        'id',
        'name',
        'role',
        'executable_path',
        'sort_order',
        'is_active',
      ]));

      final rows = await db.query('remote_tools');
      expect(rows, hasLength(1));
      expect(rows.single['name'], 'RDP Tool');
      expect(rows.single['executable_path'], r'C:\mstsc.exe');
      expect(rows.single['sort_order'], 1);

      await dropRemoteToolsLaunchModeColumnOnOpen(db);

      final columnsAfterSecond = await _remoteToolsColumns(db);
      expect(columnsAfterSecond, isNot(contains('launch_mode')));
    } finally {
      await db.close();
    }
  });
}
