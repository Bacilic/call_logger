// Συμβόλαιο Δ17: το άνοιγμα/φόρτωμα της Λάμπας ΔΙΑΒΑΖΕΙ — δεν γράφει.
// Η cache αναζήτησης χτίζεται read-only· τα σχήματα/artifacts εξασφαλίζονται
// μόνο στα γραπτά μονοπάτια (updateSection, applier, χειροκίνητη αναδόμηση).
//
//   flutter test test/core/database/old_database/lamp_cache_build_read_only_test.dart

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
    tempDir = await Directory.systemTemp.createTemp('lamp-read-only-build-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    repository = OldEquipmentRepository();
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedMinimal() async {
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('equipment', <String, Object?>{
        'code': 100,
        'description': 'PC Γραφείου',
      });
    } finally {
      await db.close();
    }
  }

  Future<Set<String>> schemaObjectNames() async {
    final db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    try {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type IN ('table','trigger','index')",
      );
      return rows.map((r) => r['name'].toString()).toSet();
    } finally {
      await db.close();
    }
  }

  test('η αναζήτηση δεν δημιουργεί search_index ούτε triggers', () async {
    await seedMinimal();
    final before = await schemaObjectNames();

    final result = await repository.globalSearch(
      dbPath,
      'γραφειου',
      maxDisplay: 10,
    );
    await LampDatabaseProvider.instance.close();

    expect(result.totalCount, 1);
    final after = await schemaObjectNames();
    // Ο πίνακας search_index δεν δημιουργείται από την αναζήτηση.
    expect(after.contains('search_index'), isFalse);
    // Κανένα νέο αντικείμενο σχήματος — το φόρτωμα είναι καθαρή ανάγνωση.
    // (Τα triggers ακεραιότητας υπάρχουν ήδη από τη δημιουργία του σχήματος.)
    expect(after, before);
  });

  test('η αναζήτηση δεν αλλάζει ούτε byte στο αρχείο της βάσης', () async {
    await seedMinimal();
    final statBefore = await File(dbPath).stat();

    await repository.globalSearch(dbPath, 'γραφειου', maxDisplay: 10);
    await LampDatabaseProvider.instance.close();

    final statAfter = await File(dbPath).stat();
    expect(statAfter.size, statBefore.size);
    expect(statAfter.modified, statBefore.modified);
  });

  test('η χειροκίνητη αναδόμηση search_index εξακολουθεί να δουλεύει '
      'σε βάση χωρίς τον πίνακα', () async {
    await seedMinimal();

    final result = await repository.rebuildLampSearchIndex(dbPath);

    expect(result.newRowCount, 1);
  });

  test('updateSection δικτύου δουλεύει σε παλιά βάση χωρίς στήλες δικτύου '
      'χωρίς να έχει προηγηθεί αναζήτηση', () async {
    // Παλιά βάση: equipment χωρίς στήλες δικτύου.
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.execute('''
        CREATE TABLE equipment (
          code INTEGER PRIMARY KEY,
          description TEXT,
          model INTEGER,
          model_original_text TEXT,
          serial_no TEXT,
          asset_no TEXT,
          state INTEGER,
          state_original_text TEXT,
          state_name TEXT,
          set_master INTEGER,
          set_master_original_text TEXT,
          contract INTEGER,
          contract_original_text TEXT,
          maintenance_contract TEXT,
          receiving_date TEXT,
          end_of_guarantee_date TEXT,
          cost TEXT,
          owner INTEGER,
          owner_original_text TEXT,
          office INTEGER,
          office_original_text TEXT,
          attributes TEXT,
          comments TEXT
        )
      ''');
      await db.insert('equipment', <String, Object?>{
        'code': 200,
        'description': 'Παλιό PC',
      });
    } finally {
      await db.close();
    }

    final result = await repository.updateSection(
      databasePath: dbPath,
      id: 200,
      sectionType: OldEquipmentSectionType.network,
      updatedFields: <String, Object?>{'ip_address': '10.0.0.5'},
    );

    expect(result.success, isTrue, reason: result.message ?? '');
    await LampDatabaseProvider.instance.close();
    final check = await openDatabase(dbPath, singleInstance: false);
    try {
      final rows = await check.query(
        'equipment',
        columns: <String>['ip_address'],
        where: 'code = 200',
      );
      expect(rows.single['ip_address'], '10.0.0.5');
    } finally {
      await check.close();
    }
  });
}
