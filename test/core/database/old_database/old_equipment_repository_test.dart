import 'dart:io';

import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
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
    tempDir = await Directory.systemTemp.createTemp('old-lamp-db-test-');
    dbPath = p.join(tempDir.path, 'lamp.sqlite');
    repository = OldEquipmentRepository();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await _seed(db);
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

  test('αλλαγή equipment.code ενημερώνει τα παιδιά set_master', () async {
    final result = await repository.updateSection(
      databasePath: dbPath,
      id: 100,
      sectionType: OldEquipmentSectionType.equipment,
      updatedFields: <String, Object?>{'code': 101},
    );

    expect(result.success, isTrue);
    await LampDatabaseProvider.instance.close();

    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      final child = await db.query(
        'equipment',
        columns: <String>['set_master'],
        where: 'code = ?',
        whereArgs: <Object?>[200],
      );
      expect(child.single['set_master'], 101);
    } finally {
      await db.close();
    }
  });

  test('απορρίπτεται κύκλος στο set_master πριν την αποθήκευση', () async {
    final result = await repository.updateSection(
      databasePath: dbPath,
      id: 100,
      sectionType: OldEquipmentSectionType.equipment,
      updatedFields: <String, Object?>{'set_master': 200},
    );

    expect(result.success, isFalse);
    expect(result.message, contains('κύκλο'));
  });

  test('απορρίπτεται διπλότυπο asset_no με φιλικό μήνυμα', () async {
    final result = await repository.updateSection(
      databasePath: dbPath,
      id: 200,
      sectionType: OldEquipmentSectionType.equipment,
      updatedFields: <String, Object?>{'asset_no': 'A-100'},
    );

    expect(result.success, isFalse);
    expect(result.message, contains('παγίου'));
  });

  test('αλλαγή γραφείου ιδιοκτήτη ενημερώνει μόνο owners (όχι αυτόματα εξοπλισμό)', () async {
    final result = await repository.updateSection(
      databasePath: dbPath,
      id: 10,
      sectionType: OldEquipmentSectionType.owner,
      updatedFields: <String, Object?>{
        'owner_office': 2,
        'owner_phones': null,
      },
    );

    expect(result.success, isTrue);
    await LampDatabaseProvider.instance.close();

    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      final owner = await db.query(
        'owners',
        columns: <String>['office', 'phones'],
        where: 'owner = ?',
        whereArgs: <Object?>[10],
      );
      final equipment = await db.query(
        'equipment',
        columns: <String>['office', 'owner'],
        where: 'code = ?',
        whereArgs: <Object?>[100],
      );
      expect(owner.single['office'], 2);
      expect(owner.single['phones'], isNull);
      expect(equipment.single['office'], 1);
      expect(equipment.single['owner'], 10);
    } finally {
      await db.close();
    }
  });

  test(
    'scanIntegrityIssues εντοπίζει duplicate_model_serial όταν συνυπάρχουν διπλότυπα',
    () async {
      await LampDatabaseProvider.instance.close();
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        await db.insert('equipment', <String, Object?>{
          'code': 2350,
          'description': 'Ποντίκι Α',
          'model': 1,
          'serial_no': 'SN-DUP-001',
        });
        await db.insert('equipment', <String, Object?>{
          'code': 2351,
          'description': 'Ποντίκι Β',
          'model': 1,
          'serial_no': 'SN-DUP-001',
        });
        await db.insert('equipment', <String, Object?>{
          'code': 2352,
          'description': 'Ποντίκι Γ',
          'model': 1,
          'serial_no': 'SN-DUP-001',
        });
        await db.insert('equipment', <String, Object?>{
          'code': 2353,
          'description': 'Ποντίκι Δ',
          'model': 1,
          'serial_no': 'SN-DUP-001',
        });
      } finally {
        await db.close();
      }

      final scan = await repository.scanIntegrityIssues(dbPath);
      final duplicateIssues = scan.issues
          .where((issue) => issue['issue_type'] == 'duplicate_model_serial')
          .toList();

      expect(duplicateIssues, hasLength(1));
      expect(duplicateIssues.single['raw_value'], 'SN-DUP-001');
      expect(
        duplicateIssues.single['message'].toString(),
        contains('4 εγγραφές'),
      );
    },
  );

  test(
    'collectDbSnapshot δεν αφήνει ανοιχτό handle — το αρχείο διαγράφεται αμέσως',
    () async {
      final snapshotPath = p.join(tempDir.path, 'snapshot_collect.db');
      await File(dbPath).copy(snapshotPath);

      final snapshot = await repository.collectDbSnapshot(snapshotPath);

      expect(snapshot.exists, isTrue);
      expect(snapshot.equipmentCount, 2);
      expect(snapshot.issuesCount, 0);

      await File(snapshotPath).delete();
      expect(await File(snapshotPath).exists(), isFalse);
    },
  );

  test(
    'scanIntegrityIssues εκδίδει serial_scientific_notation για επιστημονικό σειριακό',
    () async {
      await LampDatabaseProvider.instance.close();
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        await db.insert('equipment', <String, Object?>{
          'code': 3100,
          'description': 'Laptop Excel',
          'model': 1,
          'serial_no': '4,928E+11',
        });
        await db.insert('equipment', <String, Object?>{
          'code': 3101,
          'description': 'Laptop κανονικό',
          'model': 1,
          'serial_no': 'SN-NORMAL-001',
        });
      } finally {
        await db.close();
      }

      final scan = await repository.scanIntegrityIssues(dbPath);
      final scientificIssues = scan.issues
          .where((issue) => issue['issue_type'] == 'serial_scientific_notation')
          .toList();

      expect(scientificIssues, hasLength(1));
      expect(scientificIssues.single['raw_value'], '4,928E+11');
      expect(scientificIssues.single['row_number'], 3100);
      expect(scientificIssues.single['column_name'], 'serial_no');
    },
  );

  test('serialExistsInLamp επιστρέφει σωστά αν υπάρχει άλλος σειριακός', () async {
    await LampDatabaseProvider.instance.close();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.insert('equipment', <String, Object?>{
        'code': 3200,
        'description': 'Εξοπλισμός Α',
        'model': 1,
        'serial_no': 'BARCODE-XYZ',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 3201,
        'description': 'Εξοπλισμός Β',
        'model': 1,
        'serial_no': 'BARCODE-XYZ',
      });
    } finally {
      await db.close();
    }

    expect(
      await repository.serialExistsInLamp(dbPath, 'BARCODE-XYZ', exceptCode: 3200),
      isTrue,
    );
    expect(
      await repository.serialExistsInLamp(dbPath, 'BARCODE-XYZ', exceptCode: 3201),
      isTrue,
    );
    expect(
      await repository.serialExistsInLamp(dbPath, 'BARCODE-XYZ', exceptCode: 9999),
      isTrue,
    );
    expect(
      await repository.serialExistsInLamp(dbPath, 'ΜΟΝΑΔΙΚΟΣ-123'),
      isFalse,
    );
    expect(
      await repository.serialExistsInLamp(dbPath, ''),
      isFalse,
    );
  });

  test('επιτρέπεται γραφείο εξοπλισμού διαφορετικό από το γραφείο του κατόχου', () async {
    final result = await repository.updateSection(
      databasePath: dbPath,
      id: 100,
      sectionType: OldEquipmentSectionType.equipment,
      updatedFields: <String, Object?>{'office_id': 2},
    );

    expect(result.success, isTrue);
    await LampDatabaseProvider.instance.close();

    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      final owner = await db.query(
        'owners',
        columns: <String>['office'],
        where: 'owner = ?',
        whereArgs: <Object?>[10],
      );
      final equipment = await db.query(
        'equipment',
        columns: <String>['office', 'owner'],
        where: 'code = ?',
        whereArgs: <Object?>[100],
      );
      expect(owner.single['office'], 1);
      expect(equipment.single['office'], 2);
      expect(equipment.single['owner'], 10);
    } finally {
      await db.close();
    }
  });
}

Future<void> _seed(Database db) async {
  await db.insert('offices', <String, Object?>{
    'office': 1,
    'office_name': 'Προμήθειες',
    'phones': '100',
  });
  await db.insert('offices', <String, Object?>{
    'office': 2,
    'office_name': 'Χρηματικό',
    'phones': '200',
  });
  await db.insert('owners', <String, Object?>{
    'owner': 10,
    'last_name': 'Παπαδόπουλος',
    'office': 1,
    'phones': '123',
  });
  await db.insert('model', <String, Object?>{
    'model': 1,
    'model_name': 'Model A',
  });
  await db.insert('contracts', <String, Object?>{
    'contract': 1,
    'contract_name': 'Contract A',
  });
  await db.insert('equipment', <String, Object?>{
    'code': 100,
    'description': 'Master',
    'model': 1,
    'serial_no': 'SN-100',
    'asset_no': 'A-100',
    'contract': 1,
    'owner': 10,
    'office': 1,
  });
  await db.insert('equipment', <String, Object?>{
    'code': 200,
    'description': 'Child',
    'model': 1,
    'serial_no': 'SN-200',
    'asset_no': 'A-200',
    'set_master': 100,
    'contract': 1,
    'office': 1,
  });
}
