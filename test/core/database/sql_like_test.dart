// Η αναζήτηση ψάχνει κατά λέξη: το % και το _ του χρήστη δεν είναι μπαλαντέρ.
//
//   flutter test test/core/database/sql_like_test.dart

import 'dart:io';

import 'package:call_logger/core/database/sql_like.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('το % και το _ του χρήστη εξουδετερώνονται', () {
    expect(SqlLike.contains('50%'), r'%50\%%');
    expect(SqlLike.startsWith('a_b'), r'a\_b%');
    expect(SqlLike.endsWith(r'c:\x'), r'%c:\\x');
  });

  test('στην ίδια τη SQLite: «50%» δεν ταιριάζει με το «2250»', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE t (v TEXT)');
    for (final v in ['medico 2250', 'μελάνι 50% γεμάτο', r'φάκελος c:\x_y']) {
      await db.insert('t', {'v': v});
    }

    Future<List<Object?>> find(String pattern) async => (await db.rawQuery(
      'SELECT v FROM t WHERE v ${SqlLike.op}',
      [pattern],
    )).map((r) => r['v']).toList();

    expect(await find(SqlLike.contains('50%')), ['μελάνι 50% γεμάτο']);
    expect(await find(SqlLike.contains('%')), ['μελάνι 50% γεμάτο']);
    expect(await find(SqlLike.contains(r'c:\x_')), [r'φάκελος c:\x_y']);
    expect(await find(SqlLike.contains('50')), hasLength(2));
  });

  // Έλεγχος αρχιτεκτονικής: κάθε `LIKE` της εφαρμογής περνά από το SqlLike.
  // Ένα σκέτο `LIKE ?` με τιμή από τον χρήστη ξαναφέρνει το «50%» που βρίσκει
  // κάθε κλήση με «50» μέσα της.
  test('κανένα σημείο δεν γράφει σκέτο LIKE ? χωρίς διαφυγή', () {
    final raw = RegExp(r'\bLIKE\s+\?', caseSensitive: false);
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.endsWith('core/database/sql_like.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (raw.hasMatch(line)) offenders.add('$path:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Γράψτε `${SqlLike.op}` με όρισμα από SqlLike.contains/…',
    );
  });
}
