import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../utils/file_picker_session.dart';
import '../utils/picker_location_memory.dart';
import '../services/application_reset_service.dart';
import '../services/settings_service.dart';
import 'database_helper.dart';
import 'database_init_progress_provider.dart';
import 'database_init_result.dart';
import 'database_init_runner.dart';

/// Τι διάλεξε ο χρήστης στον επιλογέα διαδρομής βάσης.
enum DatabasePickKind { databaseFile, backupArchive }

/// Αποτέλεσμα επιλογής αρχείου/φακέλου βάσης (όχι γυμνή διαδρομή).
class DatabasePickSelection {
  const DatabasePickSelection({required this.kind, required this.path});

  final DatabasePickKind kind;
  final String path;

  bool get isBackupArchive => kind == DatabasePickKind.backupArchive;
}

/// Κατάταξη επιλεγμένης διαδρομής από την κατάληξη μόνο — χωρίς δίσκο/UI.
DatabasePickKind classifyPickedDatabasePath(String path) {
  final ext = p.extension(path.trim()).toLowerCase();
  if (ext == '.zip') return DatabasePickKind.backupArchive;
  return DatabasePickKind.databaseFile;
}

/// Επιλογή αρχείου `.db` (προτίμηση) ή φακέλου → `call_logger.db` μέσα.
/// Επιστρέφει `null` αν ακυρώθηκε η επιλογή ή έγινε refocus σε ανοιχτό picker.
Future<DatabasePickSelection?> pickDatabasePathWithSystemPicker() async {
  final session = await FilePickerSession.run(
    _pickDatabasePathWithSystemPickerImpl,
  );
  if (session.refocusedExisting) return null;
  return session.value;
}

Future<DatabasePickSelection?> _pickDatabasePathWithSystemPickerImpl() async {
  // Στοχευμένο αρχικό άνοιγμα: ο φάκελος της τρέχουσας βάσης, όχι η καθολική
  // «τελευταία θέση» των Windows που μολύνεται από άσχετους επιλογείς.
  final initialDirectory = await const PickerLocationMemory(
    'database_file',
  ).initialDirectory(pathHint: await SettingsService().getDatabasePath());

  final fileResult = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['db', 'zip'],
    dialogTitle: 'Επιλογή αρχείου βάσης (.db) ή αντιγράφου (.zip)',
    initialDirectory: initialDirectory,
  );

  if (fileResult == null) {
    return null;
  }

  if (fileResult.files.isNotEmpty && fileResult.files.single.path != null) {
    final path = fileResult.files.single.path!.trim();
    if (path.isEmpty) return null;
    return DatabasePickSelection(
      kind: classifyPickedDatabasePath(path),
      path: path,
    );
  }

  final dirPath = await FilePicker.getDirectoryPath(
    dialogTitle: 'Επιλογή φακέλου βάσης δεδομένων',
    initialDirectory: initialDirectory,
  );

  if (dirPath != null && dirPath.trim().isNotEmpty) {
    return DatabasePickSelection(
      kind: DatabasePickKind.databaseFile,
      path: p.join(dirPath, 'call_logger.db'),
    );
  }

  return null;
}

/// Εκτελεστής ελέγχων αρχικοποίησης (προεπιλογή: [runDatabaseInitChecks]).
typedef DatabaseInitChecksRunner =
    Future<DatabaseInitRunnerResult> Function({
      bool closeConnectionFirst,
      DatabaseInitProgressNotifier? progressNotifier,
    });

/// Κλείσιμο της τρέχουσας σύνδεσης (προεπιλογή: [DatabaseHelper.closeConnection]).
typedef DatabaseConnectionCloser = Future<void> Function();

Future<void> _closeCurrentConnection() =>
    DatabaseHelper.instance.closeConnection();

/// Ορίζει διαδρομή, τρέχει ελέγχους αρχικοποίησης· σε αποτυχία επαναφέρει την προηγούμενη.
///
/// Η προηγούμενη σύνδεση κλείνει **εδώ**, πριν αλλάξει η ρύθμιση διαδρομής, και
/// ο εκτελεστής των ελέγχων δεν ξανακλείνει. Το κλείσιμο πρέπει να γίνει
/// οπωσδήποτε: το [DatabaseHelper.initializeDatabase] επιστρέφει την ήδη
/// ανοιχτή σύνδεση, οπότε μια σύνδεση που έμεινε ανοιχτή θα οδηγούσε σε
/// επαλήθευση της ΠΑΛΙΑΣ βάσης με αναφορά επιτυχίας για τη νέα διαδρομή.
Future<({bool ok, DatabaseInitRunnerResult runner})> setAndVerifyDatabasePath(
  String trimmed, {
  DatabaseInitChecksRunner runInitChecks = runDatabaseInitChecks,
  DatabaseConnectionCloser closeConnection = _closeCurrentConnection,
}) async {
  final settings = SettingsService();
  final wasUnconfigured = await settings.isDatabaseUnconfigured();
  final previous = wasUnconfigured ? null : await settings.getDatabasePath();

  try {
    await closeConnection();
  } catch (e, st) {
    // Έξοδος πριν γραφτεί η νέα διαδρομή: η ρύθμιση μένει άθικτη, οπότε δεν
    // χρειάζεται επαναφορά.
    return (
      ok: false,
      runner: DatabaseInitRunnerResult(
        result: DatabaseInitResult.fromException(e, trimmed, st),
        isLocalDevMode: false,
      ),
    );
  }

  late DatabaseInitRunnerResult runner;
  try {
    await settings.setDatabasePath(trimmed);
    runner = await runInitChecks();
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
    if (runner.result.recoveryKind !=
        DatabaseInitRecoveryKind.schemaUpgradeConsent) {
      await settings.forgetRecentDatabasePath(trimmed);
    }
    if (!wasUnconfigured && previous != null) {
      try {
        await settings.setDatabasePath(previous);
      } catch (_) {}
    } else if (wasUnconfigured) {
      await settings.markDatabaseUnconfigured();
    }
    return (ok: false, runner: runner);
  }

  await settings.recordVerifiedDatabasePath(trimmed);

  if (await ApplicationResetService.instance.hasPendingReset()) {
    await ApplicationResetService.instance.commitPendingReset();
  }

  return (ok: true, runner: runner);
}
