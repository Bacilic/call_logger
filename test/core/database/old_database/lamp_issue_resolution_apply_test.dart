import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/resolution_log_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late LampIssueResolutionService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-resolution-apply-');
    dbPath = p.join(tempDir.path, 'lamp.sqlite');
    service = LampIssueResolutionService();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      // Στην πραγματική Λάμπα τα διπλότυπα υπάρχουν ήδη στη βάση· αφαιρούμε
      // τους δείκτες μοναδικότητας ώστε τα σενάρια επίλυσης να σπέρνονται.
      await db.execute('DROP INDEX IF EXISTS ux_equipment_asset_no_clean');
      await db.execute('DROP INDEX IF EXISTS ux_equipment_model_serial_no_clean');
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

  group('Λάμπα · εφαρμογή αποφάσεων επίλυσης ETL', () {
    test(
      'ομάδα 3 εξοπλισμών με ίδιο asset_no: reassign σε έναν κρατά την ουρά ανοιχτή',
      () async {
        await _seedBaseReferenceData(dbPath);
        await _insertEquipment(
          dbPath,
          code: 1001,
          assetNo: 'DUP-ASSET',
          description: 'Εξοπλισμός Α',
        );
        await _insertEquipment(
          dbPath,
          code: 1002,
          assetNo: 'DUP-ASSET',
          description: 'Εξοπλισμός Β',
        );
        await _insertEquipment(
          dbPath,
          code: 1003,
          assetNo: 'DUP-ASSET',
          description: 'Εξοπλισμός Γ',
        );
        final issueId = await _insertIssue(
          dbPath,
          issueType: 'duplicate_asset_no',
          rawValue: 'DUP-ASSET',
          columnName: 'asset_no',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.duplicateAssetNo,
        );
        final proposal = proposals.single;
        final option = proposal.options.firstWhere(
          (o) => o.metadata['targetCode'] == 1001,
        );

        await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(
              proposal: proposal,
              option: option,
              textInput: 'ASSET-ΝΕΟ-1001',
            ),
          ],
        );

        final remaining = await _countIssues(dbPath, issueType: 'duplicate_asset_no');
        expect(remaining, 1);
        expect(await _issueExists(dbPath, issueId), isTrue);
        final assetCounts = await _assetNoCounts(dbPath, 'DUP-ASSET');
        expect(assetCounts, 2);
      },
    );

    test(
      'ομάδα 2 εξοπλισμών με ίδιο asset_no: reassign σε έναν κλείνει την ουρά',
      () async {
        await _seedBaseReferenceData(dbPath);
        await _insertEquipment(
          dbPath,
          code: 2001,
          assetNo: 'PAIR-ASSET',
          description: 'Εξοπλισμός 1',
        );
        await _insertEquipment(
          dbPath,
          code: 2002,
          assetNo: 'PAIR-ASSET',
          description: 'Εξοπλισμός 2',
        );
        final issueId = await _insertIssue(
          dbPath,
          issueType: 'duplicate_asset_no',
          rawValue: 'PAIR-ASSET',
          columnName: 'asset_no',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.duplicateAssetNo,
        );
        final proposal = proposals.single;
        final option = proposal.options.firstWhere(
          (o) => o.metadata['targetCode'] == 2001,
        );

        await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(
              proposal: proposal,
              option: option,
              textInput: 'ASSET-ΜΟΝΑΔΙΚΟ',
            ),
          ],
        );

        expect(await _issueExists(dbPath, issueId), isFalse);
        expect(await _assetNoCounts(dbPath, 'PAIR-ASSET'), 1);
      },
    );

    test(
      'δύο non_numeric_fk γραφείου με ίδιο κείμενο: «Νέα εγγραφή» δημιουργεί ένα γραφείο',
      () async {
        await _seedBaseReferenceData(dbPath);
        const officeText = 'Νέο Τμήμα Δοκιμής';
        await _insertEquipment(
          dbPath,
          code: 3001,
          officeOriginalText: officeText,
          description: 'Εξοπλισμός Γραφείο 1',
        );
        await _insertEquipment(
          dbPath,
          code: 3002,
          officeOriginalText: officeText,
          description: 'Εξοπλισμός Γραφείο 2',
        );
        final issueId1 = await _insertIssue(
          dbPath,
          issueType: 'non_numeric_fk',
          rawValue: officeText,
          columnName: 'office',
          rowNumber: 3001,
        );
        final issueId2 = await _insertIssue(
          dbPath,
          issueType: 'non_numeric_fk',
          rawValue: officeText,
          columnName: 'office',
          rowNumber: 3002,
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.nonNumericFk,
        );
        expect(proposals.length, 2);

        for (final proposal in proposals) {
          expect(proposal.proposedAction, LampIssueResolutionAction.createNew);
          await service.applyDecisions(
            databasePath: dbPath,
            decisions: <LampIssueResolutionDecision>[
              LampIssueResolutionDecision(proposal: proposal),
            ],
          );
        }

        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final offices = await db.query(
            'offices',
            where: 'office_name = ?',
            whereArgs: <Object?>[officeText],
          );
          expect(offices.length, 1);
          final officeId = offices.single['office'] as int;

          final equipment = await db.query(
            'equipment',
            columns: <String>['code', 'office'],
            where: 'code IN (?, ?)',
            whereArgs: <Object?>[3001, 3002],
            orderBy: 'code ASC',
          );
          expect(equipment.map((row) => row['office']).toList(), <Object?>[officeId, officeId]);
        } finally {
          await db.close();
        }

        expect(await _issueExists(dbPath, issueId1), isFalse);
        expect(await _issueExists(dbPath, issueId2), isFalse);
      },
    );

    test(
      '«Νέα εγγραφή» με κείμενο που δεν υπάρχει δημιουργεί μία νέα εγγραφή γραφείου',
      () async {
        await _seedBaseReferenceData(dbPath);
        const officeText = 'Μοναδικό Γραφείο XYZ';
        await _insertEquipment(
          dbPath,
          code: 3101,
          officeOriginalText: officeText,
        );
        await _insertIssue(
          dbPath,
          issueType: 'non_numeric_fk',
          rawValue: officeText,
          columnName: 'office',
          rowNumber: 3101,
        );

        final proposal = (await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.nonNumericFk,
        )).single;

        final result = await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(proposal: proposal),
          ],
        );

        expect(result.created, 1);
        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final offices = await db.query('offices');
          expect(offices.length, 2);
          expect(
            offices.where((row) => row['office_name'] == officeText).length,
            1,
          );
        } finally {
          await db.close();
        }
      },
    );

    test(
      'reassign asset_no σε τιμή που υπάρχει ήδη αποτυγχάνει με φιλικό μήνυμα',
      () async {
        await _seedBaseReferenceData(dbPath);
        await _insertEquipment(
          dbPath,
          code: 4001,
          assetNo: '1101',
          description: 'Κάτοχος 1101',
        );
        await _insertEquipment(
          dbPath,
          code: 4002,
          assetNo: 'DUP-REASSIGN',
          description: 'Διπλότυπο',
        );
        await _insertEquipment(
          dbPath,
          code: 4003,
          assetNo: 'DUP-REASSIGN',
          description: 'Διπλότυπο 2',
        );
        await _insertIssue(
          dbPath,
          issueType: 'duplicate_asset_no',
          rawValue: 'DUP-REASSIGN',
          columnName: 'asset_no',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.duplicateAssetNo,
        );
        final proposal = proposals.single;
        final option = proposal.options.firstWhere(
          (o) => o.metadata['targetCode'] == 4002,
        );

        final result = await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(
              proposal: proposal,
              option: option,
              textInput: '1101',
            ),
          ],
        );

        expect(result.unresolved, 1);
        expect(result.errors.single, contains('1101'));
        expect(result.errors.single, contains('4001'));

        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final row = await db.query(
            'equipment',
            columns: <String>['asset_no'],
            where: 'code = ?',
            whereArgs: <Object?>[4002],
          );
          expect(row.single['asset_no'], 'DUP-REASSIGN');
        } finally {
          await db.close();
        }
      },
    );

    test(
      'δύο ομάδες διπλότυπου σειριακού με ίδιο κείμενο αλλά διαφορετικό μοντέλο: επίλυση μίας κρατά την άλλη στην ουρά',
      () async {
        await _seedBaseReferenceData(dbPath);
        await _insertModel(dbPath, model: 10, name: 'Model Ten');
        await _insertModel(dbPath, model: 20, name: 'Model Twenty');
        await _insertEquipment(
          dbPath,
          code: 5001,
          model: 10,
          serialNo: 'SHARED-SN',
        );
        await _insertEquipment(
          dbPath,
          code: 5002,
          model: 10,
          serialNo: 'SHARED-SN',
        );
        await _insertEquipment(
          dbPath,
          code: 6001,
          model: 20,
          serialNo: 'SHARED-SN',
        );
        await _insertEquipment(
          dbPath,
          code: 6002,
          model: 20,
          serialNo: 'SHARED-SN',
        );
        final issueModel10 = await _insertIssue(
          dbPath,
          issueType: 'duplicate_model_serial',
          rawValue: 'SHARED-SN',
          columnName: 'serial_no',
        );
        final issueModel20 = await _insertIssue(
          dbPath,
          issueType: 'duplicate_model_serial',
          rawValue: 'SHARED-SN',
          columnName: 'serial_no',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.duplicateModelSerial,
        );
        final proposalModel10 = proposals.firstWhere(
          (p) => p.metadata['model'] == 10,
        );
        final option = proposalModel10.options.firstWhere(
          (o) => o.metadata['targetCode'] == 5001,
        );

        await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(
              proposal: proposalModel10,
              option: option,
              textInput: 'SN-ΜΟΝΑΔΙΚΟ-10',
            ),
          ],
        );

        expect(await _issueExists(dbPath, issueModel10), isFalse);
        expect(await _issueExists(dbPath, issueModel20), isTrue);
      },
    );

    test(
      'reassign serial σε τιμή που υπάρχει σε άλλο μοντέλο επιτρέπεται',
      () async {
        await _seedBaseReferenceData(dbPath);
        await _insertModel(dbPath, model: 11, name: 'Model Eleven');
        await _insertModel(dbPath, model: 22, name: 'Model TwentyTwo');
        await _insertEquipment(
          dbPath,
          code: 7001,
          model: 11,
          serialNo: 'UNIQUE-SN-11',
        );
        await _insertEquipment(
          dbPath,
          code: 7002,
          model: 11,
          serialNo: 'DUP-SN-11',
        );
        await _insertEquipment(
          dbPath,
          code: 7003,
          model: 11,
          serialNo: 'DUP-SN-11',
        );
        await _insertEquipment(
          dbPath,
          code: 8001,
          model: 22,
          serialNo: 'CROSS-MODEL',
        );
        await _insertIssue(
          dbPath,
          issueType: 'duplicate_model_serial',
          rawValue: 'DUP-SN-11',
          columnName: 'serial_no',
        );

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.duplicateModelSerial,
        );
        final proposal = proposals.singleWhere(
          (p) => p.metadata['model'] == 11,
        );
        final option = proposal.options.firstWhere(
          (o) => o.metadata['targetCode'] == 7002,
        );

        final result = await service.applyDecisions(
          databasePath: dbPath,
          decisions: <LampIssueResolutionDecision>[
            LampIssueResolutionDecision(
              proposal: proposal,
              option: option,
              textInput: 'CROSS-MODEL',
            ),
          ],
        );

        expect(result.unresolved, 0);
        expect(result.errors, isEmpty);

        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final updated = await db.query(
            'equipment',
            columns: <String>['model', 'serial_no'],
            where: 'code = ?',
            whereArgs: <Object?>[7002],
          );
          expect(updated.single['model'], 11);
          expect(updated.single['serial_no'], 'CROSS-MODEL');
        } finally {
          await db.close();
        }
      },
    );

    test(
      'τρεις διαδοχικές applySingleDecision παράγουν τρία ζεύγη έναρξης/ολοκλήρωσης',
      () async {
        final decisions = await _threeOfficeAutoDecisions(dbPath, service);
        final startLogs = <String>[];

        for (final decision in decisions) {
          await service.applySingleDecision(
            databasePath: dbPath,
            decision: decision,
            onLog: (entry) {
              if (entry.message.startsWith('Έναρξη εφαρμογής')) {
                startLogs.add(entry.message);
              }
            },
          );
        }

        expect(startLogs, hasLength(3));
        expect(startLogs.every((m) => m.contains('1 αποφάσεων')), isTrue);
      },
    );

    test(
      'παρτίδα 3 αυτόματων αποφάσεων: μία έναρξη και συγχωνευμένο αποτέλεσμα',
      () async {
        final decisions = await _threeOfficeAutoDecisions(dbPath, service);
        final startLogs = <String>[];
        final completeLogs = <String>[];

        final result = await service.applyDecisions(
          databasePath: dbPath,
          decisions: decisions,
          onLog: (entry) {
            if (entry.message.startsWith('Έναρξη εφαρμογής')) {
              startLogs.add(entry.message);
            }
            if (entry.message.startsWith('Ολοκληρώθηκε η εφαρμογή')) {
              completeLogs.add(entry.message);
            }
          },
        );

        expect(startLogs, hasLength(1));
        expect(startLogs.single, contains('3 αποφάσεων'));
        expect(completeLogs, hasLength(1));
        expect(result.resolved, 3);
        expect(result.unresolved, 0);
        expect(result.errors, isEmpty);
      },
    );

    test(
      'ακύρωση μέσα σε παρτίδα: εφαρμόζεται μόνο η πρώτη απόφαση',
      () async {
        final decisions = await _threeOfficeAutoDecisions(dbPath, service);
        final cancelToken = ResolutionCancelToken();
        var appliedCount = 0;

        final result = await service.applyDecisions(
          databasePath: dbPath,
          decisions: decisions,
          cancelToken: cancelToken,
          onDecisionApplied: (_) {
            appliedCount++;
            cancelToken.cancel();
          },
        );

        expect(appliedCount, 1);
        expect(result.resolved, 1);
        expect(
          await _countIssues(dbPath, issueType: 'non_numeric_fk'),
          2,
        );
      },
    );
  });
}

Future<List<LampIssueResolutionDecision>> _threeOfficeAutoDecisions(
  String dbPath,
  LampIssueResolutionService service,
) async {
  await _seedBaseReferenceData(dbPath);
  const officeText = 'Βασικό Γραφείο';
  for (final code in <int>[9001, 9002, 9003]) {
    await _insertEquipment(
      dbPath,
      code: code,
      officeOriginalText: officeText,
    );
    await _insertIssue(
      dbPath,
      issueType: 'non_numeric_fk',
      rawValue: officeText,
      columnName: 'office',
      rowNumber: code,
    );
  }

  final proposals = await service.analyzeIssues(
    databasePath: dbPath,
    issueType: LampIssueType.nonNumericFk,
  );
  expect(proposals, hasLength(3));
  expect(proposals.every((p) => p.canApplyAutomatically), isTrue);
  return proposals
      .map((p) => LampIssueResolutionDecision(proposal: p))
      .toList();
}
Future<void> _seedBaseReferenceData(String dbPath) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    await db.insert('offices', <String, Object?>{
      'office': 1,
      'office_name': 'Βασικό Γραφείο',
    });
    await db.insert('model', <String, Object?>{
      'model': 1,
      'model_name': 'Model Base',
    });
    await db.insert('contracts', <String, Object?>{
      'contract': 1,
      'contract_name': 'Contract Base',
    });
  } finally {
    await db.close();
  }
}

Future<void> _insertModel(
  String dbPath, {
  required int model,
  required String name,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    await db.insert('model', <String, Object?>{
      'model': model,
      'model_name': name,
    });
  } finally {
    await db.close();
  }
}

Future<void> _insertEquipment(
  String dbPath, {
  required int code,
  String? assetNo,
  String? serialNo,
  int model = 1,
  int? office,
  String? officeOriginalText,
  String? description,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    await db.insert('equipment', <String, Object?>{
      'code': code,
      'description': description ?? 'Εξοπλισμός $code',
      'model': model,
      'asset_no': ?assetNo,
      'serial_no': ?serialNo,
      'office': ?office,
      'office_original_text': ?officeOriginalText,
    });
  } finally {
    await db.close();
  }
}

Future<int> _insertIssue(
  String dbPath, {
  required String issueType,
  required String rawValue,
  required String columnName,
  int? rowNumber,
}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    return await db.insert('data_issues', <String, Object?>{
      'sheet': 'integrity_scan',
      'issue_type': issueType,
      'raw_value': rawValue,
      'column_name': columnName,
      'row_number': rowNumber,
      'message': 'δοκιμαστικό πρόβλημα',
      'created_at': '2026-01-01T00:00:00',
    });
  } finally {
    await db.close();
  }
}

Future<int> _countIssues(String dbPath, {required String issueType}) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM data_issues WHERE issue_type = ?',
      <Object?>[issueType],
    );
    return rows.first['count'] as int;
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

Future<int> _assetNoCounts(String dbPath, String assetNo) async {
  final db = await openDatabase(dbPath, singleInstance: false);
  try {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM equipment WHERE asset_no = ?',
      <Object?>[assetNo],
    );
    return rows.first['count'] as int;
  } finally {
    await db.close();
  }
}
