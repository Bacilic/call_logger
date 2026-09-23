// Το στιγμιότυπο αντικαθιστά την ανάγνωση ολόκληρου του αρχείου μέσα από το
// δίκτυο (έλεγχος ακεραιότητας, αντίγραφο ασφαλείας). Φυλάμε ό,τι υπόσχεται:
// πιστό αντίγραφο, κλείδωμα που αφήνεται πάντα, όριο που σταματά πραγματικά.
//
//   flutter test test/core/database/database_snapshot_test.dart

import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/database/database_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

Future<String> _createDb(Directory dir, String name, {bool wal = false}) async {
  final path = p.join(dir.path, name);
  final db = await openDatabase(path, singleInstance: false);
  await db.rawQuery('PRAGMA journal_mode = ${wal ? 'WAL' : 'DELETE'}');
  await db.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY, note TEXT)');
  final batch = db.batch();
  for (var i = 0; i < 3000; i++) {
    batch.insert('sample', {'note': 'γραμμή γεμίσματος $i'});
  }
  await batch.commit(noResult: true);
  await db.close();
  return path;
}

/// Μπορεί κάποιος άλλος να γράψει **αμέσως**, χωρίς καμία αναμονή;
Future<bool> _canWriteImmediately(String path) async {
  final db = await openDatabase(path, singleInstance: false);
  try {
    await db.rawQuery('PRAGMA busy_timeout = 0');
    await db.execute('BEGIN EXCLUSIVE');
    await db.execute('COMMIT');
    return true;
  } on DatabaseException {
    return false;
  } finally {
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_snapshot_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('το αντίγραφο είναι πιστό byte προς byte', () async {
    final path = await _createDb(tempDir, 'pisto.db');

    final snapshot = await takeDatabaseSnapshot(path);
    addTearDown(snapshot.dispose);

    final original = await File(path).readAsBytes();
    expect(await File(snapshot.path).readAsBytes(), original);
    expect(snapshot.stats.bytes, original.length);
  });

  test('μετά το στιγμιότυπο το κλείδωμα έχει αφεθεί', () async {
    final path = await _createDb(tempDir, 'kleidoma.db');

    final snapshot = await takeDatabaseSnapshot(path);
    addTearDown(snapshot.dispose);

    expect(await _canWriteImmediately(path), isTrue);
  });

  test('όσο κρατά η αντιγραφή, κανείς δεν ολοκληρώνει εγγραφή', () async {
    final path = await _createDb(tempDir, 'synepeia.db');
    bool? writableDuringCopy;

    final snapshot = await takeDatabaseSnapshot(
      path,
      whileLocked: () async {
        writableDuringCopy = await _canWriteImmediately(path);
      },
    );
    addTearDown(snapshot.dispose);

    expect(writableDuringCopy, isFalse);
  });

  test('όριο που λήγει ΜΕΣΑ στην αντιγραφή: σταματά, αφήνει το κλείδωμα, '
      'σβήνει το μισό αρχείο', () async {
    final path = await _createDb(tempDir, 'orio.db');
    final before = _snapshotDirs();
    var clockReads = 0;

    await expectLater(
      takeDatabaseSnapshot(
        path,
        chunkSize: 4096,
        deadline: DateTime(2000, 6),
        // Πρώτη ανάγνωση (πριν από την αντιγραφή): εντός ορίου. Μετά το
        // πρώτο κομμάτι: εκτός.
        now: () => clockReads++ == 0 ? DateTime(2000) : DateTime(2001),
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(clockReads, 2, reason: 'πρέπει να σταμάτησε μετά το 1ο κομμάτι');

    expect(await _canWriteImmediately(path), isTrue);
    expect(_snapshotDirs().difference(before), isEmpty);
  });

  test('βάση σε WAL: δεν αντιγράφεται, και το κλείδωμα αφήνεται', () async {
    final path = await _createDb(tempDir, 'wal.db', wal: true);

    await expectLater(
      takeDatabaseSnapshot(path),
      throwsA(isA<DatabaseSnapshotUnsupported>()),
    );

    expect(await _canWriteImmediately(path), isTrue);
  });

  test(
    'κείμενο μετονομασμένο σε .db: απορρίπτεται πριν από κάθε αντιγραφή',
    () async {
      final path = p.join(tempDir.path, 'Hospital.db');
      await File(path).writeAsString('Αυτό είναι απλό κείμενο.\n' * 500);
      final before = _snapshotDirs();

      await expectLater(
        takeDatabaseSnapshot(path),
        throwsA(isA<DatabaseException>()),
      );

      expect(_snapshotDirs().difference(before), isEmpty);
    },
  );
}

Set<String> _snapshotDirs() => Directory.systemTemp
    .listSync()
    .whereType<Directory>()
    .map((d) => d.path)
    .where((path) => p.basename(path).startsWith('call_logger_snapshot_'))
    .toSet();
