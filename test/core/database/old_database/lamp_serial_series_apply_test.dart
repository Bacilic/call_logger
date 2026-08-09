// Η αρίθμηση σειράς από τον οδηγό ως τη βάση.
//
// Σενάριο 09/08: 61 ομάδες διπλότυπων σειριακών, 224 εγγραφές. Ο οδηγός
// πρόσφερε μόνο «μία εγγραφή τη φορά», οπότε η ομάδα των 20 barcode scanner
// απαιτούσε είκοσι περάσματα.
//
//   flutter test test/core/database/old_database/lamp_serial_series_apply_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_reporter.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-serial-series-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('model', <String, Object?>{
        'model': 554,
        'model_name': 'Hand Held Barcode Scanner',
        'category_name': 'Περιφερειακό',
      });
      await db.insert('model', <String, Object?>{
        'model': 434,
        'model_name': 'Windows 10 Pro',
        'category_name': 'Λογισμικό',
      });
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<T> withDb<T>(Future<T> Function(Database db) action) async {
    await LampDatabaseProvider.instance.close();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      return await action(db);
    } finally {
      await db.close();
    }
  }

  Future<void> seedGroup({
    required int model,
    required String serial,
    required List<int> codes,
    List<String> extraSerials = const <String>[],
  }) async {
    await withDb((db) async {
      for (final code in codes) {
        await db.insert('equipment', <String, Object?>{
          'code': code,
          'description': 'HANDHELD BARCODE SCANNER',
          'model': model,
          'serial_no': serial,
        });
      }
      var next = 9000;
      for (final extra in extraSerials) {
        await db.insert('equipment', <String, Object?>{
          'code': next++,
          'description': 'άλλο μηχάνημα ίδιου μοντέλου',
          'model': model,
          'serial_no': extra,
        });
      }
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'duplicate_model_serial',
        'sheet': 'integrity_scan',
        'column_name': 'serial_no',
        'raw_value': serial,
        'status': 'open',
        'created_at': '2026-08-09T10:00:00.000',
      });
    });
  }

  Future<LampIssueResolutionProposal> proposal() async {
    return (await LampIssueResolutionService().analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.duplicateModelSerial,
    )).single;
  }

  Future<List<String?>> serialsOf(List<int> codes) async {
    return withDb((db) async {
      final result = <String?>[];
      for (final code in codes) {
        final row = (await db.query(
          'equipment',
          columns: <String>['serial_no'],
          where: 'code = ?',
          whereArgs: <Object?>[code],
        )).single;
        result.add(row['serial_no'] as String?);
      }
      return result;
    });
  }

  test('μία ενέργεια αριθμεί ολόκληρη την ομάδα', () async {
    await seedGroup(
      model: 554,
      serial: 'NLSHR125070',
      codes: <int>[3818, 3819, 3822],
    );

    final target = await proposal();
    final option = target.options.firstWhere(
      (o) => o.requiresSerialSeriesInput,
    );
    expect(option.label, contains('3 εγγραφές'));

    await LampIssueResolutionService().applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: option,
        serialSeriesTemplate: 'NLSHR125070-$kLampSeriesCounterToken',
      ),
    );

    expect(await serialsOf(<int>[3818, 3819, 3822]), <String>[
      'NLSHR125070-1',
      'NLSHR125070-2',
      'NLSHR125070-3',
    ]);
    expect(
      await withDb((db) => db.query('data_issues', where: "status = 'open'")),
      isEmpty,
    );
  });

  test('η μορφή με παρενθέσεις εφαρμόζεται', () async {
    await seedGroup(model: 554, serial: 'NLSHR125070', codes: <int>[10, 20]);
    final target = await proposal();

    await LampIssueResolutionService().applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: target.options.firstWhere((o) => o.requiresSerialSeriesInput),
        serialSeriesTemplate: 'NLSHR125070 ($kLampSeriesCounterToken)',
      ),
    );

    expect(await serialsOf(<int>[10, 20]), <String>[
      'NLSHR125070 (1)',
      'NLSHR125070 (2)',
    ]);
  });

  test('κατειλημμένος αριθμός προσπερνιέται αντί να πατηθεί', () async {
    await seedGroup(
      model: 554,
      serial: 'NLSHR125070',
      codes: <int>[10, 20],
      extraSerials: <String>['NLSHR125070-1', 'NLSHR125070-3'],
    );
    final target = await proposal();

    await LampIssueResolutionService().applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: target.options.firstWhere((o) => o.requiresSerialSeriesInput),
        serialSeriesTemplate: 'NLSHR125070-$kLampSeriesCounterToken',
      ),
    );

    expect(
      await serialsOf(<int>[10, 20]),
      <String>['NLSHR125070-2', 'NLSHR125070-4'],
      reason: greekExpectMsg(
        'Πατώντας κατειλημμένο αριθμό η συναλλαγή θα έσκαγε στη μέση και η '
        'σειρά θα έμενε μισοαριθμημένη',
      ),
    );
  });

  test('κλειδί άδειας: η αρίθμηση δεν προσφέρεται, μόνο η αποδοχή', () async {
    await seedGroup(
      model: 434,
      serial: '3XNJY-9J4GT-Y7DJ8-9R98M-XBT6Y',
      codes: <int>[2593, 2674],
    );
    final target = await proposal();

    expect(
      target.options.where((o) => o.requiresSerialSeriesInput),
      isEmpty,
      reason: greekExpectMsg(
        'Είκοσι υπολογιστές με την ίδια volume license δεν είναι σφάλμα· η '
        'αρίθμηση θα κατέστρεφε την πληροφορία',
      ),
    );

    final accept = target.options.firstWhere(
      (o) => o.metadata['operation'] == 'accept_duplicate_serial',
    );
    await LampIssueResolutionService().applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: accept,
      ),
    );

    expect(
      await serialsOf(<int>[2593, 2674]),
      <String>['3XNJY-9J4GT-Y7DJ8-9R98M-XBT6Y', '3XNJY-9J4GT-Y7DJ8-9R98M-XBT6Y'],
      reason: greekExpectMsg(
        'Η αποδοχή κλείνει την εκκρεμότητα χωρίς να αγγίξει δεδομένα',
      ),
    );
    expect(
      await withDb((db) => db.query('data_issues', where: "status = 'open'")),
      isEmpty,
    );
  });

  test('η αρίθμηση συνεχίζει υπάρχουσα σειρά', () async {
    await seedGroup(
      model: 554,
      serial: '10NXMP0026001',
      codes: <int>[10, 20],
      extraSerials: <String>[
        for (var i = 1; i <= 10; i++) '10NXMP0026001-$i',
      ],
    );
    final target = await proposal();

    await LampIssueResolutionService().applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: target.options.firstWhere((o) => o.requiresSerialSeriesInput),
        serialSeriesTemplate: '10NXMP0026001-$kLampSeriesCounterToken',
      ),
    );

    expect(await serialsOf(<int>[10, 20]), <String>[
      '10NXMP0026001-11',
      '10NXMP0026001-12',
    ]);
  });

  test('σειριακός σκέτη παύλα: το μοντέλο γίνεται αφετηρία', () async {
    // Τα τέσσερα πληκτρολόγια Dell της Λάμπας — η αρίθμηση πάνω στην παύλα
    // παρήγαγε «--1».
    await seedGroup(model: 554, serial: '-', codes: <int>[789, 790]);

    final target = await proposal();
    final option = target.options.firstWhere(
      (o) => o.requiresSerialSeriesInput,
    );

    expect(
      option.metadata['suggestedTemplate'],
      'Hand Held Barcode Scanner (554)-$kLampSeriesCounterToken',
      reason: greekExpectMsg(
        'Η σύμβαση του νοσοκομείου βάζει το μοντέλο όταν το μηχάνημα δεν '
        'φέρει δικό του σειριακό',
      ),
    );

    // Χωρίς ρητό πρότυπο εφαρμόζεται η πρόταση του αναλυτή.
    await LampIssueResolutionService().applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: option,
      ),
    );

    expect(await serialsOf(<int>[789, 790]), <String>[
      'Hand Held Barcode Scanner (554)-1',
      'Hand Held Barcode Scanner (554)-2',
    ]);
  });

  test('πρότυπο χωρίς τελεστή απορρίπτεται', () async {
    await seedGroup(model: 554, serial: 'NLSHR125070', codes: <int>[10, 20]);
    final target = await proposal();

    final result = await LampIssueResolutionService().applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: target.options.firstWhere((o) => o.requiresSerialSeriesInput),
        serialSeriesTemplate: 'NLSHR125070',
      ),
    );

    expect(result.unresolved, 1);
    expect(
      await serialsOf(<int>[10, 20]),
      <String>['NLSHR125070', 'NLSHR125070'],
      reason: greekExpectMsg(
        'Χωρίς τον τελεστή και οι δύο θα έπαιρναν την ίδια τιμή — καλύτερα '
        'να αποτύχει η ενέργεια παρά να μείνει το διπλότυπο μεταμφιεσμένο',
      ),
    );
  });
}
