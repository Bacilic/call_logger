import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Πίνακες βάσης ανάγνωσης χωρίς indexes/triggers (παλιό .db σχήμα).
const List<String> _bareTableCreateStatements = <String>[
  '''
  CREATE TABLE offices (
    office INTEGER PRIMARY KEY,
    office_name TEXT,
    organization INTEGER,
    organization_name TEXT,
    department INTEGER,
    department_name TEXT,
    responsible INTEGER,
    responsible_original_text TEXT,
    e_mail TEXT,
    phones TEXT,
    building TEXT,
    level INTEGER
  )
  ''',
  '''
  CREATE TABLE owners (
    owner INTEGER PRIMARY KEY,
    last_name TEXT,
    first_name TEXT,
    office INTEGER,
    office_original_text TEXT,
    e_mail TEXT,
    phones TEXT,
    FOREIGN KEY (office) REFERENCES offices(office)
      ON DELETE RESTRICT ON UPDATE CASCADE
  )
  ''',
  '''
  CREATE TABLE model (
    model INTEGER PRIMARY KEY,
    model_name TEXT,
    category_code INTEGER,
    category_code_original_text TEXT,
    category_name TEXT,
    subcategory_code INTEGER,
    subcategory_code_original_text TEXT,
    subcategory_name TEXT,
    manufacturer INTEGER,
    manufacturer_original_text TEXT,
    manufacturer_name TEXT,
    manufacturer_code TEXT,
    attributes TEXT,
    consumables TEXT,
    network_connectivity INTEGER
  )
  ''',
  '''
  CREATE TABLE contracts (
    contract INTEGER PRIMARY KEY,
    contract_name TEXT,
    category INTEGER,
    category_original_text TEXT,
    category_name TEXT,
    supplier INTEGER,
    supplier_original_text TEXT,
    supplier_name TEXT,
    start_date TEXT,
    end_date TEXT,
    declaration TEXT,
    award TEXT,
    cost TEXT,
    committee TEXT,
    comments TEXT
  )
  ''',
  '''
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
    comments TEXT,
    ip_address TEXT,
    network_name TEXT,
    network_source TEXT,
    network_node TEXT,
    network_vlan TEXT,
    network_mac TEXT,
    network_description TEXT,
    network_comments TEXT,
    FOREIGN KEY (model) REFERENCES model(model)
      ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (contract) REFERENCES contracts(contract)
      ON DELETE SET NULL ON UPDATE CASCADE,
    FOREIGN KEY (owner) REFERENCES owners(owner)
      ON DELETE SET NULL ON UPDATE CASCADE,
    FOREIGN KEY (office) REFERENCES offices(office)
      ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (set_master) REFERENCES equipment(code)
      ON DELETE RESTRICT ON UPDATE CASCADE
  )
  ''',
];

Future<Set<String>> _sqliteMasterNames(
  Database db, {
  required String type,
}) async {
  final rows = await db.rawQuery(
    'SELECT name FROM sqlite_master WHERE type = ?',
    <Object?>[type],
  );
  return rows.map((row) => row['name'] as String).toSet();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late OldEquipmentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-read-schema-upgrade-');
    dbPath = p.join(tempDir.path, 'bare_lamp.db');
    repository = OldEquipmentRepository();
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'preloadSearchCache προσθέτει indexes και triggers σε βάση χωρίς ακεραιότητα',
    () async {
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        for (final statement in _bareTableCreateStatements) {
          await db.execute(statement);
        }
        await db.insert('offices', <String, Object?>{
          'office': 1,
          'office_name': 'Γραφείο Α',
        });
        await db.insert('owners', <String, Object?>{
          'owner': 1,
          'last_name': 'Παπαδόπουλος',
          'first_name': 'Γιώργος',
          'office': 1,
        });
        await db.insert('model', <String, Object?>{
          'model': 1,
          'model_name': 'Desktop',
        });
        await db.insert('equipment', <String, Object?>{
          'code': 100,
          'description': 'PC',
          'model': 1,
          'serial_no': 'SN-100',
          'owner': 1,
          'office': 1,
        });

        final triggersBefore = await _sqliteMasterNames(db, type: 'trigger');
        final indexesBefore = await _sqliteMasterNames(db, type: 'index');
        expect(
          triggersBefore.contains('trg_equipment_set_master_no_self_insert'),
          isFalse,
        );
        expect(indexesBefore.contains('idx_equipment_serial_no'), isFalse);
      } finally {
        await db.close();
      }

      await repository.preloadSearchCache(dbPath);
      await LampDatabaseProvider.instance.close();

      final verifyDb = await openDatabase(dbPath, singleInstance: false);
      try {
        final triggersAfter = await _sqliteMasterNames(verifyDb, type: 'trigger');
        final indexesAfter = await _sqliteMasterNames(verifyDb, type: 'index');
        expect(
          triggersAfter.contains('trg_equipment_set_master_no_self_insert'),
          isTrue,
        );
        expect(indexesAfter.contains('idx_equipment_serial_no'), isTrue);
      } finally {
        await verifyDb.close();
      }
    },
  );

  test(
    'αποτυχία UNIQUE ux_owners_identity_key_clean δεν μπλοκάρει τα υπόλοιπα artifacts',
    () async {
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        for (final statement in _bareTableCreateStatements) {
          await db.execute(statement);
        }
        await db.insert('offices', <String, Object?>{
          'office': 1,
          'office_name': 'Γραφείο Α',
        });
        // Ίδια κανονικοποιημένη ταυτότητα → σπάει το UNIQUE index.
        await db.insert('owners', <String, Object?>{
          'owner': 1,
          'last_name': 'Παπαδόπουλος',
          'first_name': 'Γιώργος',
          'office': 1,
        });
        await db.insert('owners', <String, Object?>{
          'owner': 2,
          'last_name': 'Παπαδόπουλος',
          'first_name': 'Γιώργος',
          'office': 1,
        });
        await db.insert('model', <String, Object?>{
          'model': 1,
          'model_name': 'Desktop',
        });
        await db.insert('equipment', <String, Object?>{
          'code': 100,
          'description': 'PC',
          'model': 1,
          'serial_no': 'SN-100',
          'owner': 1,
          'office': 1,
        });
      } finally {
        await db.close();
      }

      await repository.preloadSearchCache(dbPath);
      await LampDatabaseProvider.instance.close();

      final verifyDb = await openDatabase(dbPath, singleInstance: false);
      try {
        final triggers = await _sqliteMasterNames(verifyDb, type: 'trigger');
        final indexes = await _sqliteMasterNames(verifyDb, type: 'index');
        expect(
          triggers.contains('trg_equipment_set_master_no_self_insert'),
          isTrue,
        );
        expect(indexes.contains('idx_equipment_serial_no'), isTrue);
        // Το UNIQUE μπορεί να λείπει λόγω διπλοτύπων — δεν πρέπει να μπλοκάρει τα άλλα.
        expect(indexes.contains('ux_owners_identity_key_clean'), isFalse);
      } finally {
        await verifyDb.close();
      }
    },
  );
}
