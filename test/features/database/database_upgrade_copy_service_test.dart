// Αντίγραφο βάσης προς αναβάθμιση — χωρίς εγγραφή στο πρωτότυπο.
//
//   flutter test test/features/database/database_upgrade_copy_service_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/features/database/services/database_upgrade_copy_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

Future<Uint8List> _bytes(String path) => File(path).readAsBytes();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    tempDir = await Directory.systemTemp.createTemp('upgrade_copy_');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('τα bytes του πρωτοτύπου μένουν αμετάβλητα', () async {
    final source = p.join(tempDir.path, 'original.db');
    await DatabaseHelper.instance.createNewDatabaseFile(source);
    final before = await _bytes(source);

    final result = await createUpgradeCopy(
      source,
      now: DateTime(2026, 7, 25),
    );
    expect(
      result.isSuccess,
      isTrue,
      reason: result.errorMessage ?? 'χωρίς μήνυμα',
    );
    expect(await _bytes(source), orderedEquals(before));
  });

  test('το αντίγραφο ανοίγει και αναβαθμίζεται κανονικά', () async {
    final source = p.join(tempDir.path, 'old_schema.db');
    await DatabaseHelper.instance.createNewDatabaseFile(source);
    final writer = await openDatabase(source, singleInstance: false);
    await writer.rawQuery('PRAGMA user_version = 30');
    await writer.close();

    final result = await createUpgradeCopy(
      source,
      now: DateTime(2026, 7, 25),
    );
    expect(result.isSuccess, isTrue);
    final copyPath = result.copyPath!;

    final upgraded = await openDatabase(
      copyPath,
      version: kDatabaseSchemaVersion,
      onUpgrade: onDatabaseUpgradeSquashed,
      singleInstance: false,
    );
    final rows = await upgraded.rawQuery('PRAGMA user_version');
    await upgraded.close();
    expect(rows.first['user_version'], kDatabaseSchemaVersion);

    final sourceVersion = await openDatabase(
      source,
      readOnly: true,
      singleInstance: false,
    ).then((db) async {
      final v = await db.rawQuery('PRAGMA user_version');
      await db.close();
      return v.first['user_version'];
    });
    expect(sourceVersion, 30);
  });

  test('αντιγράφονται τα sidecars όταν υπάρχουν', () async {
    final source = p.join(tempDir.path, 'with_wal.db');
    await DatabaseHelper.instance.createNewDatabaseFile(source);
    final writer = await openDatabase(source, singleInstance: false);
    await writer.execute('PRAGMA journal_mode = WAL');
    await writer.execute('CREATE TABLE IF NOT EXISTS t (id INTEGER)');
    await writer.insert('t', <String, Object?>{'id': 1});
    final holder = await openDatabase(source, singleInstance: false);
    addTearDown(() async {
      if (holder.isOpen) await holder.close();
    });
    await holder.rawQuery('SELECT 1');
    await writer.close();

    final wal = File('$source-wal');
    expect(await wal.exists(), isTrue);

    final result = await createUpgradeCopy(
      source,
      now: DateTime(2026, 7, 25),
    );
    expect(result.isSuccess, isTrue);
    final copyPath = result.copyPath!;
    // Μετά το checkpoint μπορεί να μην υπάρχει -wal στο πρωτότυπο,
    // αλλά αν υπάρχει ακόμη, πρέπει να υπάρχει και στο αντίγραφο.
    if (await File('$source-wal').exists()) {
      expect(await File('$copyPath-wal').exists(), isTrue);
    }
    if (await File('$source-shm').exists()) {
      expect(await File('$copyPath-shm').exists(), isTrue);
    }
  });

  test('σε ομώνυμο αρχείο μπαίνει η ώρα, όχι αύξων αριθμός', () async {
    final source = p.join(tempDir.path, 'clash.db');
    await DatabaseHelper.instance.createNewDatabaseFile(source);
    final now = DateTime(2026, 7, 25, 14, 32, 7);
    await File(
      p.join(tempDir.path, 'clash_αναβαθμισμένη_25-07-2026.db'),
    ).writeAsString('occupied');

    final result = await createUpgradeCopy(source, now: now);
    expect(result.isSuccess, isTrue);
    expect(
      p.basename(result.copyPath!),
      'clash_αναβαθμισμένη_25-07-2026_14-32.db',
    );
  });

  test('δεύτερη σύγκρουση στο ίδιο λεπτό κλιμακώνει σε δευτερόλεπτα', () async {
    final source = p.join(tempDir.path, 'clash2.db');
    await DatabaseHelper.instance.createNewDatabaseFile(source);
    final now = DateTime(2026, 7, 25, 14, 32, 7);
    for (final name in [
      'clash2_αναβαθμισμένη_25-07-2026.db',
      'clash2_αναβαθμισμένη_25-07-2026_14-32.db',
    ]) {
      await File(p.join(tempDir.path, name)).writeAsString('occupied');
    }

    final result = await createUpgradeCopy(source, now: now);
    expect(result.isSuccess, isTrue);
    expect(
      p.basename(result.copyPath!),
      'clash2_αναβαθμισμένη_25-07-2026_14-32-07.db',
    );
  });

  test('αντίγραφο αντιγράφου δεν συσσωρεύει επιθήματα', () async {
    final source = p.join(
      tempDir.path,
      'παλιά_βάση_2023_αναβαθμισμένη_25-07-2026.db',
    );
    await DatabaseHelper.instance.createNewDatabaseFile(source);

    final result = await createUpgradeCopy(
      source,
      now: DateTime(2026, 7, 25, 14, 32),
    );
    expect(result.isSuccess, isTrue);
    expect(
      p.basename(result.copyPath!),
      'παλιά_βάση_2023_αναβαθμισμένη_25-07-2026_14-32.db',
      reason: 'το παλιό επίθημα αντικαθίσταται αντί να προστίθεται δεύτερο',
    );
  });

  test('δεν αντικαθίσταται υπάρχον αρχείο με το ίδιο όνομα', () async {
    final source = p.join(tempDir.path, 'clash.db');
    await DatabaseHelper.instance.createNewDatabaseFile(source);
    final stamp = '25-07-2026';
    final firstName = 'clash_αναβαθμισμένη_$stamp.db';
    final occupied = File(p.join(tempDir.path, firstName));
    await occupied.writeAsString('occupied');

    final result = await createUpgradeCopy(
      source,
      now: DateTime(2026, 7, 25),
    );
    expect(result.isSuccess, isTrue);
    expect(result.copyPath, isNot(equals(occupied.path)));
    expect(await occupied.readAsString(), 'occupied');
    expect(await File(result.copyPath!).exists(), isTrue);
  });
}
