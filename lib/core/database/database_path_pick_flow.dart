import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../services/settings_service.dart';
import 'database_helper.dart';
import 'database_init_result.dart';
import 'database_init_runner.dart';

/// Επιλογή αρχείου `.db` (προτίμηση) ή φακέλου → `call_logger.db` μέσα.
/// Επιστρέφει `null` αν ακυρώθηκε η επιλογή.
Future<String?> pickDatabasePathWithSystemPicker() async {
  final fileResult = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['db'],
    dialogTitle: 'Επιλογή αρχείου βάσης δεδομένων (.db)',
  );

  if (fileResult != null &&
      fileResult.files.isNotEmpty &&
      fileResult.files.single.path != null) {
    return fileResult.files.single.path!.trim();
  }

  final dirPath = await FilePicker.getDirectoryPath(
    dialogTitle: 'Επιλογή φακέλου βάσης δεδομένων',
  );

  if (dirPath != null && dirPath.trim().isNotEmpty) {
    return p.join(dirPath, 'call_logger.db');
  }

  return null;
}

/// Ορίζει διαδρομή, τρέχει ελέγχους αρχικοποίησης· σε αποτυχία επαναφέρει την προηγούμενη.
Future<({bool ok, DatabaseInitRunnerResult runner})> setAndVerifyDatabasePath(
  String trimmed,
) async {
  final settings = SettingsService();
  final previous = await settings.getDatabasePath();
  late DatabaseInitRunnerResult runner;
  try {
    try {
      await DatabaseHelper.instance.closeConnection();
    } catch (_) {}
    await settings.setDatabasePath(trimmed);
    runner = await runDatabaseInitChecks(closeConnectionFirst: true);
  } catch (e, st) {
    runner = DatabaseInitRunnerResult(
      result: DatabaseInitResult.fromException(e, trimmed, st),
      isLocalDevMode: false,
    );
  }

  if (!runner.result.isSuccess) {
    try {
      await DatabaseHelper.instance.closeConnection();
    } catch (_) {}
    try {
      await settings.setDatabasePath(previous);
    } catch (_) {}
    return (ok: false, runner: runner);
  }

  return (ok: true, runner: runner);
}
