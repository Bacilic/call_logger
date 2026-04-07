import 'package:file_picker/file_picker.dart';

import '../database/database_helper.dart';
import '../database/directory_repository.dart';
import 'excel_parser.dart';
import 'import_types.dart';

export 'excel_parser.dart' show ImportResult;

/// Υπηρεσία εισαγωγής δεδομένων από Master Excel (.xlsx).
class ImportService {
  Future<ImportResult> importFromExcel({
    required void Function(String message, [ImportLogLevel? level]) onLog,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return const ImportResult(success: false, errorMessage: 'Δεν επιλέχθηκε αρχείο.');
      }

      final path = result.files.single.path;
      if (path == null || path.isEmpty) {
        return const ImportResult(success: false, errorMessage: 'Δεν ήταν δυνατή η ανάγνωση του αρχείου.');
      }

      final parseResult = await ExcelParser().parseMasterExcel(path, onLog);
      if (!parseResult.success) return parseResult;

      final owners = parseResult.preparedOwners ?? [];
      final equipment = parseResult.preparedEquipment ?? [];

      int usersInserted = 0;
      int equipmentInserted = 0;

      if (owners.isNotEmpty || equipment.isNotEmpty) {
        onLog('Εκκαθάριση υπαρχόντων δεδομένων...', ImportLogLevel.info);
        final dbImp = await DatabaseHelper.instance.database;
        final dirImp = DirectoryRepository(dbImp);
        await dirImp.clearImportedData();
        onLog('Εισαγωγή δεδομένων στη βάση...');
        final r = await dirImp.importPreparedData(owners, equipment);
        usersInserted = r.usersInserted;
        equipmentInserted = r.equipmentInserted;
        onLog(
          'Εισήχθησαν $usersInserted χρήστες και $equipmentInserted υπολογιστές.',
          ImportLogLevel.success,
        );
      }

      return ImportResult(
        success: true,
        totalCount: usersInserted + equipmentInserted,
        usersPrepared: parseResult.usersPrepared,
        equipmentPrepared: parseResult.equipmentPrepared,
        usersInserted: usersInserted,
        equipmentInserted: equipmentInserted,
        skipped: parseResult.skipped,
        errors: parseResult.errors,
      );
    } catch (e) {
      onLog('ΣΦΑΛΜΑ: $e', ImportLogLevel.error);
      return ImportResult(success: false, errorMessage: e.toString());
    }
  }
}
