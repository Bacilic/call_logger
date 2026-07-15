import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_issue_matching_engine.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_support.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LampIssueResolutionSupport support;

  setUp(() {
    support = LampIssueResolutionSupport(LampIssueMatchingEngine());
  });

  group('lampLabelledId', () {
    test('υπαρκτό id με ετικέτα → «Όνομα (73)»', () {
      expect(
        lampLabelledId(<int, String>{73: 'Διοικητικό ΚΥ Ξυλοκάστρου'}, 73),
        'Διοικητικό ΚΥ Ξυλοκάστρου (73)',
      );
    });

    test('ορφανό id χωρίς ετικέτα → σκέτο id', () {
      expect(lampLabelledId(const <int, String>{}, 73), '73');
    });

    test('null → «-»', () {
      expect(lampLabelledId(const <int, String>{}, null), '-');
    });
  });

  group('equipmentSummary', () {
    final row = <String, Object?>{
      'code': 2667,
      'description': 'PC Test',
      'model': 410,
      'serial_no': 'SN-001',
      'office': 73,
      'owner': 243,
    };

    test('με labels εμφανίζει «Όνομα (id)» για FK πεδία', () {
      final labels = LampFkLabelMaps(
        modelLabelById: <int, String>{410: 'Windows 7 Pro'},
        officeLabelById: <int, String>{73: 'Διοικητικό ΚΥ Ξυλοκάστρου'},
        ownerLabelById: <int, String>{243: 'Εξεταστήριο 2'},
      );

      expect(
        support.equipmentSummary(row, labels: labels),
        'κωδικός=2667 · PC Test · '
            'μοντέλο=Windows 7 Pro (410) · σειριακός=SN-001 · '
            'γραφείο=Διοικητικό ΚΥ Ξυλοκάστρου (73) · υπάλληλος=Εξεταστήριο 2 (243)',
      );
    });

    test('χωρίς labels (empty) κρατά γυμνά ids', () {
      expect(
        support.equipmentSummary(row),
        'κωδικός=2667 · PC Test · '
            'μοντέλο=410 · σειριακός=SN-001 · '
            'γραφείο=73 · υπάλληλος=243',
      );
    });
  });

  group('loadFkLabelMaps', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lamp-fk-labels-test-');
      dbPath = p.join(tempDir.path, 'lamp.sqlite');
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        await createOldDatabaseSchema(db);
        await db.insert('model', <String, Object?>{
          'model': 410,
          'model_name': 'Windows 7 Pro',
        });
        await db.insert('offices', <String, Object?>{
          'office': 73,
          'office_name': 'Διοικητικό ΚΥ',
          'department_name': 'Ξυλοκάστρου',
        });
        await db.insert('owners', <String, Object?>{
          'owner': 243,
          'last_name': 'Εξεταστήριο',
          'first_name': '2',
        });
      } finally {
        await db.close();
      }
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('διαβάζει σωστά model, office και owner', () async {
      final db = await openDatabase(dbPath, singleInstance: false);
      try {
        final labels = await support.loadFkLabelMaps(db);

        expect(labels.modelLabelById[410], 'Windows 7 Pro');
        expect(
          labels.officeLabelById[73],
          'Διοικητικό ΚΥ Ξυλοκάστρου',
        );
        expect(labels.ownerLabelById[243], 'Εξεταστήριο 2');
      } finally {
        await db.close();
      }
    });
  });
}
