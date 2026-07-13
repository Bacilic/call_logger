import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
// ignore: unnecessary_import
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_models.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_excel_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justkawal_excel_updated/justkawal_excel_updated.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int _equipmentCodePartialOwner = 8842;
const int _equipmentCodeExactOwner = 8850;
const int _excelRowPartialOwner = 6;
const int _excelRowExactOwner = 7;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late LampIssueResolutionService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-fk-row-semantics-');
    service = LampIssueResolutionService();
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Λάμπα · σημασιολογία row_number σε FK issues εξοπλισμού', () {
    test(
      'import καταγράφει row_number = κωδικός εξοπλισμού όχι γραμμή Excel',
      () async {
        final dbPath = await _importSemanticsWorkbook(tempDir);

        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final issues = await db.query(
            'data_issues',
            where: 'issue_type = ? AND column_name = ?',
            whereArgs: <Object?>['non_numeric_fk', 'owner'],
            orderBy: 'raw_value ASC',
          );
          expect(issues.length, 2);

          final partial = issues.firstWhere(
            (row) => row['raw_value'] == 'Πατσαρίκα',
          );
          final exact = issues.firstWhere(
            (row) => row['raw_value'] == 'Άννα Πατσαρίκα',
          );

          expect(partial['row_number'], _equipmentCodePartialOwner);
          expect(partial['row_number'], isNot(_excelRowPartialOwner));
          expect(exact['row_number'], _equipmentCodeExactOwner);
          expect(exact['row_number'], isNot(_excelRowExactOwner));
        } finally {
          await db.close();
        }
      },
    );

    test(
      'αναλυτής FK για ακριβές όνομα υπαλλήλου δίνει πρόταση υψηλής βεβαιότητας',
      () async {
        final dbPath = await _importSemanticsWorkbook(tempDir);

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.nonNumericFk,
        );
        final proposal = proposals.singleWhere(
          (p) => p.originalValue == 'Άννα Πατσαρίκα',
        );

        expect(proposal.proposedAction, isNot(LampIssueResolutionAction.unresolved));
        expect(proposal.confidence, greaterThanOrEqualTo(80));
        expect(
          proposal.options.any(
            (option) => option.action == LampIssueResolutionAction.autoFix,
          ),
          isTrue,
        );
        expect(proposal.notes, isNot(contains('Δεν βρέθηκε εξοπλισμός')));
      },
    );

    test(
      'αναλυτής FK για μερικό όνομα υπαλλήλου δίνει πρόταση προς έγκριση',
      () async {
        final dbPath = await _importSemanticsWorkbook(tempDir);

        final proposals = await service.analyzeIssues(
          databasePath: dbPath,
          issueType: LampIssueType.nonNumericFk,
        );
        final proposal = proposals.singleWhere(
          (p) => p.originalValue == 'Πατσαρίκα',
        );

        expect(proposal.proposedAction, LampIssueResolutionAction.manualReview);
        expect(proposal.confidence, greaterThan(0));
        expect(proposal.options, isNotEmpty);
        expect(proposal.notes, isNot(contains('Δεν βρέθηκε εξοπλισμός')));
      },
    );
  });
}

Future<String> _importSemanticsWorkbook(Directory tempDir) async {
  final excel = Excel.createExcel();
  void appendTexts(String sheet, List<String> values) {
    excel[sheet].appendRow(
      values.map<CellValue?>(TextCellValue.new).toList(),
    );
  }

  appendTexts('offices', <String>['office', 'office_name']);
  appendTexts('offices', <String>['1', 'Γραφείο Δοκιμής']);

  appendTexts('owners', <String>['owner', 'last_name', 'first_name']);
  appendTexts('owners', <String>['50', 'Πατσαρίκα', 'Άννα']);

  appendTexts('model', <String>['model', 'model_name']);
  appendTexts('model', <String>['1', 'Γενικό μοντέλο']);

  appendTexts('contracts', <String>['contract', 'contract_name']);
  appendTexts('contracts', <String>['1', 'Γενική σύμβαση']);

  appendTexts('equipment', <String>['code', 'description', 'owner']);
  appendTexts('equipment', <String>['100', 'Γεμίσματος 1', '50']);
  appendTexts('equipment', <String>['200', 'Γεμίσματος 2', '50']);
  appendTexts('equipment', <String>['300', 'Γεμίσματος 3', '50']);
  appendTexts('equipment', <String>['400', 'Γεμίσματος 4', '50']);
  appendTexts('equipment', <String>[
    '$_equipmentCodePartialOwner',
    'Εξοπλισμός μερικού ονόματος',
    'Πατσαρίκα',
  ]);
  appendTexts('equipment', <String>[
    '$_equipmentCodeExactOwner',
    'Εξοπλισμός πλήρους ονόματος',
    'Άννα Πατσαρίκα',
  ]);

  final xlsxPath = p.join(tempDir.path, 'fk_semantics.xlsx');
  File(xlsxPath).writeAsBytesSync(excel.encode()!);
  final dbPath = p.join(tempDir.path, 'fk_semantics.db');

  await OldExcelImporter().importExcel(
    excelPath: xlsxPath,
    databasePath: dbPath,
  );
  return dbPath;
}
