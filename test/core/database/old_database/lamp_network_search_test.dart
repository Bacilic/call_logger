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
    tempDir = await Directory.systemTemp.createTemp('lamp-network-search-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    repository = OldEquipmentRepository();
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedWithNetworkFields() async {
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('equipment', <String, Object?>{
        'code': 3900,
        'description': 'Πολυμηχάνημα Α4',
        'ip_address': '10.10.223.43',
        'network_name': 'PR3900',
        'network_node': '710',
        'network_vlan': 'Οικονομικού',
        'network_mac': '70B5E869B696',
        'network_description': 'ΠολυμηχάνημαΑ4',
        'network_comments': 'Ασύρματο δίκτυο',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 100,
        'description': 'Οθόνη LG',
      });
    } finally {
      await db.close();
    }
  }

  group('καθολική αναζήτηση στα πεδία δικτύου', () {
    test('βρίσκει εξοπλισμό με IP, MAC, hostname, VLAN και σχόλια δικτύου',
        () async {
      await seedWithNetworkFields();
      for (final query in <String>[
        '10.10.223.43',
        '70B5E869B696',
        'PR3900',
        'Οικονομικού',
        'Ασύρματο δίκτυο',
      ]) {
        final result = await repository.globalSearch(
          dbPath,
          query,
          maxDisplay: 10,
        );
        expect(result.totalCount, 1, reason: 'αναζήτηση: $query');
        expect(result.rows.single['code'], 3900, reason: 'αναζήτηση: $query');
      }
    });

    test('παλιά βάση χωρίς στήλες δικτύου: η αναζήτηση δεν σπάει', () async {
      // Παλιό σχήμα: όλοι οι πίνακες ως έχουν, αλλά equipment ΧΩΡΙΣ τις
      // στήλες δικτύου (όπως βάσεις πριν από τον εμπλουτισμό).
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        for (final statement in oldDatabaseCreateStatements) {
          if (statement.contains('CREATE TABLE equipment')) continue;
          await db.execute(statement);
        }
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
          'code': 7,
          'description': 'Εκτυπωτής Lexmark',
        });
      } finally {
        await db.close();
      }

      final result = await repository.globalSearch(
        dbPath,
        'Lexmark',
        maxDisplay: 10,
      );
      expect(result.totalCount, 1);
      expect(result.rows.single['ip_address'], isNull);
    });
  });

  group('updateSection για την κάρτα Δίκτυο', () {
    test('ενημερώνει τα πεδία δικτύου του εξοπλισμού', () async {
      await seedWithNetworkFields();
      final result = await repository.updateSection(
        databasePath: dbPath,
        id: 3900,
        sectionType: OldEquipmentSectionType.network,
        updatedFields: <String, Object?>{
          'ip_address': '10.10.223.99',
          'network_vlan': 'Νέο VLAN',
          'network_comments': 'Διορθώθηκε χειροκίνητα',
        },
      );
      expect(result.success, isTrue, reason: result.message);
      await LampDatabaseProvider.instance.close();

      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        final row = (await db.query(
          'equipment',
          where: 'code = ?',
          whereArgs: <Object?>[3900],
        )).single;
        expect(row['ip_address'], '10.10.223.99');
        expect(row['network_vlan'], 'Νέο VLAN');
        expect(row['network_comments'], 'Διορθώθηκε χειροκίνητα');
        expect(row['network_name'], 'PR3900');
      } finally {
        await db.close();
      }
    });

    test(
      'γραμμή με παλιό ελάττωμα set_master→εαυτό: οι σημειώσεις δικτύου '
      'αποθηκεύονται κανονικά',
      () async {
        // Κληρονομιά Λάμπας: set_master = code (χωρίς triggers, όπως οι
        // υπάρχουσες βάσεις πριν τα integrity artifacts).
        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          for (final statement in oldDatabaseCreateStatements) {
            await db.execute(statement);
          }
          await db.insert('equipment', <String, Object?>{
            'code': 3402,
            'description': 'Υπολογιστής Dell Vostro 3888',
            'set_master': 3402,
          });
        } finally {
          await db.close();
        }

        final result = await repository.updateSection(
          databasePath: dbPath,
          id: 3402,
          sectionType: OldEquipmentSectionType.network,
          updatedFields: <String, Object?>{
            'network_comments': 'Σημείωση δικτύου',
          },
        );
        expect(result.success, isTrue, reason: result.message);

        await LampDatabaseProvider.instance.close();
        final check = await openDatabase(dbPath, singleInstance: false);
        try {
          final row = (await check.query(
            'equipment',
            where: 'code = ?',
            whereArgs: <Object?>[3402],
          )).single;
          expect(row['network_comments'], 'Σημείωση δικτύου');
          expect(row['set_master'], 3402); // το παλιό ελάττωμα δεν πειράχτηκε
        } finally {
          await check.close();
        }
      },
    );

    test('η αλλαγή του ίδιου του set_master σε εαυτό απορρίπτεται ακόμη',
        () async {
      await seedWithNetworkFields();
      final result = await repository.updateSection(
        databasePath: dbPath,
        id: 3900,
        sectionType: OldEquipmentSectionType.equipment,
        updatedFields: <String, Object?>{'set_master': 3900},
      );
      expect(result.success, isFalse);
      expect(result.message, contains('set_master'));
    });

    test('δεν επιτρέπει πεδία εκτός δικτύου μέσω της κάρτας Δίκτυο', () async {
      await seedWithNetworkFields();
      final result = await repository.updateSection(
        databasePath: dbPath,
        id: 3900,
        sectionType: OldEquipmentSectionType.network,
        updatedFields: <String, Object?>{'description': 'πειραγμένο'},
      );
      expect(result.success, isFalse);
    });
  });
}
