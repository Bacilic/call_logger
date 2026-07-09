import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const Set<String> _scannerNetworkIssueTypes = <String>{
  'network_duplicate_ip',
  'network_duplicate_name',
  'network_invalid_ip',
  'network_name_code_mismatch',
};

const Set<String> _importNetworkIssueTypes = <String>{
  'network_no_hostname',
  'network_hostname_unmatched',
  'network_duplicate_hostname',
  'network_code_not_found',
  'network_ip_in_comments',
  'network_model_mismatch',
  'network_sheet_invalid',
};

List<Map<String, Object?>> _scannerNetworkIssues(
  List<Map<String, Object?>> issues,
) {
  return issues
      .where((issue) => _scannerNetworkIssueTypes.contains(issue['issue_type']))
      .toList();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late OldEquipmentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('old-lamp-network-scan-');
    repository = OldEquipmentRepository();
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('σαρωτής ακεραιότητας · δεδομένα δικτύου', () {
    test('διπλή IP — ένα εύρημα ανά εξοπλισμό της ομάδας', () async {
      final dbPath = await _createDbWithNetworkColumns(tempDir);
      await _insertEquipment(dbPath, code: 101, ipAddress: '192.168.1.10');
      await _insertEquipment(dbPath, code: 102, ipAddress: '192.168.1.10');

      final result = await repository.scanIntegrityIssues(dbPath);
      final networkIssues = _scannerNetworkIssues(result.issues);

      expect(networkIssues, hasLength(2));
      expect(
        networkIssues.map((i) => i['issue_type']).toSet(),
        <String>{'network_duplicate_ip'},
      );
      expect(
        networkIssues.map((i) => i['row_number']).toSet(),
        <Object?>{101, 102},
      );
      for (final issue in networkIssues) {
        expect(issue['column_name'], 'ip_address');
        expect(issue['message'], contains('192.168.1.10'));
      }
    });

    test('διπλό network_name — ένα εύρημα ανά εξοπλισμό της ομάδας', () async {
      final dbPath = await _createDbWithNetworkColumns(tempDir);
      await _insertEquipment(dbPath, code: 201, networkName: 'LOGISTIRIO');
      await _insertEquipment(dbPath, code: 202, networkName: 'logistirio');

      final result = await repository.scanIntegrityIssues(dbPath);
      final networkIssues = _scannerNetworkIssues(result.issues)
          .where((issue) => issue['issue_type'] == 'network_duplicate_name')
          .toList();

      expect(networkIssues, hasLength(2));
      expect(
        networkIssues.map((i) => i['row_number']).toSet(),
        <Object?>{201, 202},
      );
      for (final issue in networkIssues) {
        expect(issue['column_name'], 'network_name');
      }
    });

    test('άκυρη IP — ευρήματα για μη έγκυρη IPv4', () async {
      final dbPath = await _createDbWithNetworkColumns(tempDir);
      await _insertEquipment(dbPath, code: 301, ipAddress: '10.10.300.5');
      await _insertEquipment(dbPath, code: 302, ipAddress: 'κείμενο');

      final result = await repository.scanIntegrityIssues(dbPath);
      final networkIssues = _scannerNetworkIssues(result.issues)
          .where((issue) => issue['issue_type'] == 'network_invalid_ip')
          .toList();

      expect(networkIssues, hasLength(2));
      expect(
        networkIssues.map((i) => i['row_number']).toSet(),
        <Object?>{301, 302},
      );
      for (final issue in networkIssues) {
        expect(issue['column_name'], 'ip_address');
      }
    });

    test('PC123 σε code 456 — εύρημα ασυμφωνίας ονόματος με κωδικό', () async {
      final dbPath = await _createDbWithNetworkColumns(tempDir);
      await _insertEquipment(dbPath, code: 456, networkName: 'PC123');

      final result = await repository.scanIntegrityIssues(dbPath);
      final networkIssues = _scannerNetworkIssues(result.issues)
          .where((issue) => issue['issue_type'] == 'network_name_code_mismatch')
          .toList();

      expect(networkIssues, hasLength(1));
      expect(networkIssues.single['row_number'], 456);
      expect(networkIssues.single['column_name'], 'network_name');
      expect(networkIssues.single['raw_value'], 'PC123');
    });

    test('PC123 σε code 123 — κανένα εύρημα ασυμφωνίας', () async {
      final dbPath = await _createDbWithNetworkColumns(tempDir);
      await _insertEquipment(dbPath, code: 123, networkName: 'PC123');

      final result = await repository.scanIntegrityIssues(dbPath);
      final networkIssues = _scannerNetworkIssues(result.issues)
          .where((issue) => issue['issue_type'] == 'network_name_code_mismatch')
          .toList();

      expect(networkIssues, isEmpty);
    });

    test('βάση χωρίς στήλες δικτύου — 0 ευρήματα χωρίς σφάλμα', () async {
      final dbPath = await _createLegacyDbWithoutNetworkColumns(tempDir);
      await _insertLegacyEquipment(dbPath, code: 101, description: 'Παλιός');

      final result = await repository.scanIntegrityIssues(dbPath);
      final networkStep = result.steps.firstWhere((s) => s.id == 'network_data');

      expect(networkStep.status, OldIntegrityStepStatus.success);
      expect(networkStep.issuesFound, 0);
      expect(_scannerNetworkIssues(result.issues), isEmpty);
    });

    test('δεύτερο τρέξιμο σαρωτή — καμία νέα εγγραφή', () async {
      final dbPath = await _createDbWithNetworkColumns(tempDir);
      await _insertEquipment(dbPath, code: 501, ipAddress: '10.0.0.5');
      await _insertEquipment(dbPath, code: 502, ipAddress: '10.0.0.5');

      final first = await repository.scanIntegrityIssues(dbPath);
      final firstNew = await repository.filterToNewDataIssuesOnly(
        dbPath,
        first.issues,
      );
      expect(firstNew, isNotEmpty);
      await repository.insertDataIssues(dbPath, firstNew);

      final second = await repository.scanIntegrityIssues(dbPath);
      final secondNew = await repository.filterToNewDataIssuesOnly(
        dbPath,
        second.issues,
      );
      expect(secondNew, isEmpty);
    });

    test(
      'δεν παράγει είδη εισαγωγής δικτύου (π.χ. network_hostname_unmatched)',
      () async {
        final dbPath = await _createDbWithNetworkColumns(tempDir);
        await _insertEquipment(
          dbPath,
          code: 601,
          ipAddress: '10.0.0.1',
          networkName: 'UNKNOWN-HOST',
        );

        final result = await repository.scanIntegrityIssues(dbPath);
        final importTypes = result.issues
            .map((issue) => issue['issue_type']?.toString())
            .whereType<String>()
            .where(_importNetworkIssueTypes.contains)
            .toList();

        expect(importTypes, isEmpty);
      },
    );
  });
}

Future<String> _createDbWithNetworkColumns(Directory tempDir) async {
  final dbPath = p.join(tempDir.path, 'network-${DateTime.now().microsecondsSinceEpoch}.sqlite');
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    await createOldDatabaseSchema(db);
  } finally {
    await db.close();
  }
  return dbPath;
}

Future<String> _createLegacyDbWithoutNetworkColumns(Directory tempDir) async {
  final dbPath = p.join(
    tempDir.path,
    'legacy-${DateTime.now().microsecondsSinceEpoch}.sqlite',
  );
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
  } finally {
    await db.close();
  }
  return dbPath;
}

Future<void> _insertEquipment(
  String dbPath, {
  required int code,
  String? ipAddress,
  String? networkName,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    await db.insert('equipment', <String, Object?>{
      'code': code,
      'description': 'EQ-$code',
      'ip_address': ?ipAddress,
      'network_name': ?networkName,
    });
  } finally {
    await db.close();
  }
}

Future<void> _insertLegacyEquipment(
  String dbPath, {
  required int code,
  required String description,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    await db.insert('equipment', <String, Object?>{
      'code': code,
      'description': description,
    });
  } finally {
    await db.close();
  }
}
