// Η ανάγνωση της Λάμπας για τη διασταύρωση: τι φέρνει σε μνήμη και πού
// σταματά το μητρώο.
//
//   flutter test test/core/database/old_database/lamp_cross_check_snapshot_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_cross_check_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  Future<void> createLamp(List<int> codes) async {
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.execute('''
        CREATE TABLE offices (
          office INTEGER PRIMARY KEY,
          office_name TEXT,
          department_name TEXT,
          phones TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE owners (
          owner INTEGER PRIMARY KEY,
          last_name TEXT,
          first_name TEXT,
          office INTEGER,
          phones TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE model (
          model INTEGER PRIMARY KEY,
          category_name TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE equipment (
          code INTEGER PRIMARY KEY,
          model INTEGER,
          state_name TEXT,
          owner INTEGER,
          office INTEGER
        )
      ''');
      for (final code in codes) {
        await db.insert('equipment', <String, Object?>{'code': code});
      }
    } finally {
      await db.close();
    }
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-snapshot-');
    dbPath = p.join(tempDir.path, 'lampa.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('το σύνορο του μητρώου είναι ο μεγαλύτερος κωδικός', () async {
    await createLamp([17, 5126, 3257]);
    final snapshot = await readLampCrossCheckSnapshot(dbPath);
    expect(snapshot.lastEquipmentCode, 5126);
    expect(snapshot.equipmentByCode.keys, containsAll(['17', '3257', '5126']));
  });

  test('άδειο μητρώο δεν ορίζει σύνορο', () async {
    await createLamp(const []);
    final snapshot = await readLampCrossCheckSnapshot(dbPath);
    expect(snapshot.lastEquipmentCode, isNull);
  });

  test('η γρήγορη ανάγνωση δίνει τον ίδιο τελευταίο κωδικό', () async {
    await createLamp([17, 5126, 3257]);
    expect(await readLampLastEquipmentCode(dbPath), 5126);
  });

  test('βάση που λείπει δεν σκάει — απλώς δεν ξέρει σύνορο', () async {
    final missing = p.join(tempDir.path, 'δεν-υπάρχει.db');
    expect(await readLampLastEquipmentCode(missing), isNull);
  });

  test('αρχείο που δεν είναι βάση δεν σκάει', () async {
    final bogus = p.join(tempDir.path, 'σκουπίδια.db');
    await File(bogus).writeAsString('δεν είμαι βάση δεδομένων');
    expect(await readLampLastEquipmentCode(bogus), isNull);
  });
}
