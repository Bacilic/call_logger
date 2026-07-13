import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/old_excel_importer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justkawal_excel_updated/justkawal_excel_updated.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('OldExcelImporter — κλειδωμένη βάση εξόδου', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lamp-locked-out-test-');
    });

    tearDown(() async {
      await LampDatabaseProvider.instance.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'ολοκληρώνει import όταν η έξοδος είναι ανοιχτή μέσω LampDatabaseProvider',
      () async {
        final excelPath = await _createMinimalExcel(tempDir.path);
        final dbPath = p.join(tempDir.path, 'locked_output.db');

        await OldExcelImporter().importExcel(
          excelPath: excelPath,
          databasePath: dbPath,
        );

        await LampDatabaseProvider.instance.open(
          dbPath,
          mode: LampDatabaseMode.read,
        );

        final result = await OldExcelImporter().importExcel(
          excelPath: excelPath,
          databasePath: dbPath,
        );

        await LampDatabaseProvider.instance.close();

        expect(result.importedRows['equipment'], 1);

        final db = await openDatabase(dbPath, singleInstance: false);
        try {
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='equipment'",
          );
          expect(tables, hasLength(1));

          final countRows = await db.rawQuery(
            'SELECT COUNT(*) AS count FROM equipment',
          );
          expect(countRows.single['count'], 1);
        } finally {
          await db.close();
        }
      },
    );

    // ΠΙΣΤΟ σενάριο: κλείδωμα από handle που ο importer ΔΕΝ ελέγχει (όπως ένα
    // δεύτερο/ξεχασμένο instance της εφαρμογής). Το `close()` του importer αγγίζει
    // μόνο το singleton, οπότε εδώ το delete ΠΡΕΠΕΙ να αποτύχει και να βγει σαφές
    // μήνυμα — αντί το import να «πετυχαίνει» ψευδώς.
    test(
      'πετά σαφές μήνυμα όταν το αρχείο κρατιέται από ξένο handle (εκτός singleton)',
      () async {
        if (!Platform.isWindows) {
          // Σε POSIX τα ανοιχτά αρχεία διαγράφονται· το mandatory locking είναι
          // συμπεριφορά Windows, όπου τρέχει η εφαρμογή.
          return;
        }
        final excelPath = await _createMinimalExcel(tempDir.path);
        final dbPath = p.join(tempDir.path, 'foreign_locked.db');

        await OldExcelImporter().importExcel(
          excelPath: excelPath,
          databasePath: dbPath,
        );

        // Ξένο handle: ανοίγει ΑΠΕΥΘΕΙΑΣ (όχι μέσω του singleton), άρα ο importer
        // δεν μπορεί να το κλείσει.
        final foreign = await openDatabase(dbPath, singleInstance: false);
        try {
          await expectLater(
            OldExcelImporter().importExcel(
              excelPath: excelPath,
              databasePath: dbPath,
            ),
            throwsA(
              isA<LampImportException>().having(
                (e) => e.message,
                'message',
                contains('χρησιμοποιείται'),
              ),
            ),
          );
        } finally {
          await foreign.close();
        }

        // Αφού κλείσει το ξένο handle, το import ξαναπετυχαίνει.
        final recovered = await OldExcelImporter().importExcel(
          excelPath: excelPath,
          databasePath: dbPath,
        );
        expect(recovered.importedRows['equipment'], 1);
      },
    );
  });
}

Future<String> _createMinimalExcel(String dir) async {
  final excel = Excel.createExcel();
  void appendTexts(String sheet, List<String> values) {
    excel[sheet].appendRow(
      values.map<CellValue?>(TextCellValue.new).toList(),
    );
  }

  appendTexts('offices', <String>['office', 'office_name']);
  appendTexts('offices', <String>['1', 'Τμήμα']);
  appendTexts('owners', <String>['owner', 'last_name']);
  appendTexts('owners', <String>['10', 'Ιδιοκτήτης']);
  appendTexts('model', <String>['model', 'model_name']);
  appendTexts('model', <String>['1', 'Model']);
  appendTexts('contracts', <String>['contract', 'contract_name']);
  appendTexts('contracts', <String>['1', 'Σύμβαση']);
  appendTexts('equipment', <String>['code', 'description', 'model', 'serial_no']);
  appendTexts('equipment', <String>['100', 'PC', '1', 'SN1']);

  final path = p.join(dir, 'minimal_locked.xlsx');
  File(path).writeAsBytesSync(excel.encode()!);
  return path;
}
