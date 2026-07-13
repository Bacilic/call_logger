import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:call_logger/core/database/old_database/old_excel_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justkawal_excel_updated/justkawal_excel_updated.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('OldExcelImporter — διπλότυποι σειριακοί αριθμοί', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    late Directory tempDir;
    late OldEquipmentRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lamp-dup-serial-test-');
      repository = OldEquipmentRepository();
    });

    tearDown(() async {
      await LampDatabaseProvider.instance.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'διατηρεί όλους τους εξοπλισμούς με ίδιο model/serial_no κατά την εισαγωγή',
      () async {
        final excel = Excel.createExcel();
        void appendTexts(String sheet, List<String> values) {
          excel[sheet].appendRow(
            values.map<CellValue?>(TextCellValue.new).toList(),
          );
        }

        appendTexts('offices', <String>['office', 'office_name']);
        appendTexts('owners', <String>['owner', 'last_name']);
        appendTexts('model', <String>['model', 'model_name']);
        appendTexts('model', <String>['42', 'Logitech M185']);
        appendTexts('contracts', <String>['contract', 'contract_name']);
        appendTexts('equipment', <String>['code', 'description', 'model', 'serial_no']);
        appendTexts('equipment', <String>['2350', 'Ποντίκι Α', '42', 'SN-DUP-001']);
        appendTexts('equipment', <String>['2351', 'Ποντίκι Β', '42', 'SN-DUP-001']);
        appendTexts('equipment', <String>['2352', 'Ποντίκι Γ', '42', 'SN-DUP-001']);
        appendTexts('equipment', <String>['2353', 'Ποντίκι Δ', '42', 'SN-DUP-001']);

        final xlsxPath = p.join(tempDir.path, 'dup_serial.xlsx');
        File(xlsxPath).writeAsBytesSync(excel.encode()!);
        final dbPath = p.join(tempDir.path, 'dup_serial.db');

        final result = await OldExcelImporter().importExcel(
          excelPath: xlsxPath,
          databasePath: dbPath,
        );
        expect(result.importedRows['equipment'], 4);

        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final countRows = await db.rawQuery(
            'SELECT COUNT(*) AS count FROM equipment',
          );
          expect(countRows.single['count'], 4);

          final codes = await db.query(
            'equipment',
            columns: <String>['code'],
            orderBy: 'code ASC',
          );
          expect(
            codes.map((row) => row['code']).toList(),
            <Object?>[2350, 2351, 2352, 2353],
          );
        } finally {
          await db.close();
        }
      },
    );

    test(
      'η σάρωση ακεραιότητας καταγράφει duplicate_model_serial χωρίς απώλεια εγγραφών',
      () async {
        final excel = Excel.createExcel();
        void appendTexts(String sheet, List<String> values) {
          excel[sheet].appendRow(
            values.map<CellValue?>(TextCellValue.new).toList(),
          );
        }

        appendTexts('offices', <String>['office', 'office_name']);
        appendTexts('owners', <String>['owner', 'last_name']);
        appendTexts('model', <String>['model', 'model_name']);
        appendTexts('model', <String>['42', 'Logitech M185']);
        appendTexts('contracts', <String>['contract', 'contract_name']);
        appendTexts('equipment', <String>['code', 'description', 'model', 'serial_no']);
        appendTexts('equipment', <String>['2350', 'Ποντίκι Α', '42', 'SN-DUP-001']);
        appendTexts('equipment', <String>['2351', 'Ποντίκι Β', '42', 'SN-DUP-001']);
        appendTexts('equipment', <String>['2352', 'Ποντίκι Γ', '42', 'SN-DUP-001']);
        appendTexts('equipment', <String>['2353', 'Ποντίκι Δ', '42', 'SN-DUP-001']);

        final xlsxPath = p.join(tempDir.path, 'dup_serial_scan.xlsx');
        File(xlsxPath).writeAsBytesSync(excel.encode()!);
        final dbPath = p.join(tempDir.path, 'dup_serial_scan.db');

        await OldExcelImporter().importExcel(
          excelPath: xlsxPath,
          databasePath: dbPath,
        );

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

        await LampDatabaseProvider.instance.close();

        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final countRows = await db.rawQuery(
            'SELECT COUNT(*) AS count FROM equipment',
          );
          expect(countRows.single['count'], 4);
        } finally {
          await db.close();
        }
      },
    );
  });
}
