import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_network_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late LampNetworkIssueResolutionService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-network-resolve-');
    dbPath = p.join(tempDir.path, 'lamp.sqlite');
    service = LampNetworkIssueResolutionService();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('model', <String, Object?>{
        'model': 1,
        'model_name': 'Model Base',
      });
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

  group('Λάμπα · επίλυση προβλημάτων δικτύου (μόνο βάση)', () {
    test('parser: 10 πεδία με κωδικό εξοπλισμού', () {
      const raw =
          'NODE1;192.168.1.10;5001;HP EliteDesk;AA:BB;10;PC5001;WG;yes;σχόλιο';
      final parsed = service.parseNetworkIssueRawValue(raw);
      expect(parsed, isNotNull);
      expect(parsed!.node, 'NODE1');
      expect(parsed.ip, '192.168.1.10');
      expect(parsed.equipmentCode, '5001');
      expect(parsed.hostname, 'PC5001');
      expect(parsed.comments, 'σχόλιο');
    });

    test('parser: 9 πεδία παλαιά μορφή χωρίς κωδικό εξοπλισμού', () {
      const raw =
          'NODE2;10.0.0.5;Lenovo T14;CC:DD;20;LAPTOP01;DOM;no;παλιό σχόλιο';
      final parsed = service.parseNetworkIssueRawValue(raw);
      expect(parsed, isNotNull);
      expect(parsed!.equipmentCode, isNull);
      expect(parsed.description, 'Lenovo T14');
      expect(parsed.hostname, 'LAPTOP01');
    });

    test(
      'επιτυχής αντιστοίχιση γράφει πεδία, σφραγίδα και διαγράφει την εγγραφή',
      () async {
        await _insertEquipment(dbPath, code: 6001);
        final issueId = await _insertNetworkIssue(
          dbPath,
          rawValue:
              'N1;172.16.0.8;6001;Dell Optiplex;11:22;30;PC6001;WG;inet;ετικέτα',
        );

        final result = await service.matchIssueToEquipment(
          databasePath: dbPath,
          issueId: issueId,
          equipmentCode: 6001,
        );

        expect(result.success, isTrue);
        expect(await _issueExists(dbPath, issueId), isFalse);

        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final row = (await db.query(
            'equipment',
            where: 'code = ?',
            whereArgs: <Object?>[6001],
          )).single;
          expect(row['ip_address'], '172.16.0.8');
          expect(row['network_name'], 'PC6001');
          expect(row['network_node'], 'N1');
          expect(row['network_vlan'], '30');
          expect(row['network_mac'], '11:22');
          expect(row['network_description'], 'Dell Optiplex');
          expect(row['network_comments'], 'ετικέτα');
          expect(
            row['network_source'],
            contains('Χειροκίνητη αντιστοίχιση'),
          );
          expect(row['network_source'], contains('N1'));
        } finally {
          await db.close();
        }
      },
    );

    test('ανύπαρκτος κωδικός εξοπλισμού → σφάλμα χωρίς αλλαγές', () async {
      final issueId = await _insertNetworkIssue(
        dbPath,
        rawValue: 'N1;1.1.1.1;9999;desc;mac;vlan;host;wg;no;c',
      );

      final result = await service.matchIssueToEquipment(
        databasePath: dbPath,
        issueId: issueId,
        equipmentCode: 9999,
      );

      expect(result.success, isFalse);
      expect(await _issueExists(dbPath, issueId), isTrue);
    });

    test('σύγκρουση χωρίς overwrite → καμία αλλαγή', () async {
      await _insertEquipment(
        dbPath,
        code: 7001,
        ip: '10.10.10.10',
        networkName: 'OLD-NAME',
      );
      final issueId = await _insertNetworkIssue(
        dbPath,
        rawValue: 'N2;20.20.20.20;7001;desc;mac;vlan;NEW-NAME;wg;no;c',
      );

      final result = await service.matchIssueToEquipment(
        databasePath: dbPath,
        issueId: issueId,
        equipmentCode: 7001,
      );

      expect(result.conflict, isTrue);
      expect(await _issueExists(dbPath, issueId), isTrue);

      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        final row = (await db.query(
          'equipment',
          where: 'code = ?',
          whereArgs: <Object?>[7001],
        )).single;
        expect(row['ip_address'], '10.10.10.10');
        expect(row['network_name'], 'OLD-NAME');
      } finally {
        await db.close();
      }
    });

    test('σύγκρουση με overwrite → αντικατάσταση', () async {
      await _insertEquipment(
        dbPath,
        code: 8001,
        ip: '1.2.3.4',
        networkName: 'OLD',
      );
      final issueId = await _insertNetworkIssue(
        dbPath,
        rawValue: 'N3;5.6.7.8;8001;desc;mac;vlan;NEW;wg;no;c',
      );

      final result = await service.matchIssueToEquipment(
        databasePath: dbPath,
        issueId: issueId,
        equipmentCode: 8001,
        overwrite: true,
      );

      expect(result.success, isTrue);
      expect(await _issueExists(dbPath, issueId), isFalse);

      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        final row = (await db.query(
          'equipment',
          where: 'code = ?',
          whereArgs: <Object?>[8001],
        )).single;
        expect(row['ip_address'], '5.6.7.8');
        expect(row['network_name'], 'NEW');
      } finally {
        await db.close();
      }
    });

    test('διαγραφή εγγραφής ουράς χωρίς αντιστοίχιση', () async {
      final issueId = await _insertNetworkIssue(
        dbPath,
        rawValue: 'N4;9.9.9.9;9001;desc;mac;vlan;host;wg;no;c',
      );

      final deleted = await service.deleteIssue(
        databasePath: dbPath,
        issueId: issueId,
      );

      expect(deleted, isTrue);
      expect(await _issueExists(dbPath, issueId), isFalse);
    });
  });
}

Future<void> _insertEquipment(
  String dbPath, {
  required int code,
  String? ip,
  String? networkName,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    await db.insert('equipment', <String, Object?>{
      'code': code,
      'description': 'Εξοπλισμός $code',
      'model': 1,
      'ip_address': ?ip,
      'network_name': ?networkName,
    });
  } finally {
    await db.close();
  }
}

Future<int> _insertNetworkIssue(
  String dbPath, {
  required String rawValue,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    return await db.insert('data_issues', <String, Object?>{
      'issue_type': 'network_hostname_unmatched',
      'raw_value': rawValue,
      'message': 'δοκιμή δικτύου',
      'created_at': '2026-01-01T00:00:00',
    });
  } finally {
    await db.close();
  }
}

Future<bool> _issueExists(String dbPath, int issueId) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    final rows = await db.query(
      'data_issues',
      where: 'id = ?',
      whereArgs: <Object?>[issueId],
    );
    return rows.isNotEmpty;
  } finally {
    await db.close();
  }
}
