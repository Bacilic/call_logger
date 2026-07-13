import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqflite.dart';

import 'lamp_database_provider.dart';

/// Κουμπί import Excel στη Λάμπα — κοινό κείμενο σε μηνύματα pending creation.
const String kLampExcelImportButtonLabel = 'Δημιουργία βάσης από Excel';

/// Αποτέλεσμα ελέγχου αρχείου .db «Λάμπα» για ανάγνωση (read path).
enum LampOldDbStatus {
  pathEmpty,
  /// Η διαδρομή ανάγνωσης ταυτίζεται με εξόδου· το .db θα δημιουργηθεί από Excel.
  pendingCreation,
  /// Διαδρομή χωρίς κατάληξη .db ή άλλο σφάλμα μορφής (π.χ. επικόλληση φακέλου).
  invalidPathFormat,
  fileMissing,
  notAFile,
  emptyFile,
  openFailed,
  notOldEquipmentDb,
  ok,
  /// Διαδρομή εξόδου χωρίς υπάρχον αρχείο — θα δημιουργηθεί από import.
  outputPendingCreation,
  /// Έγκυρη βάση Λάμπας στη διαδρομή εξόδου — θα ξαναδημιουργηθεί από import.
  outputWillUpdate,
}

class LampOldDbCheckResult {
  const LampOldDbCheckResult(
    this.status, {
    this.technicalDetail,
    this.pendingDbFileName,
    this.pendingFolderPath,
    this.pendingExcelFileName,
  });

  final LampOldDbStatus status;
  final String? technicalDetail;
  final String? pendingDbFileName;
  final String? pendingFolderPath;
  final String? pendingExcelFileName;

  String get userMessageGreek {
    switch (status) {
      case LampOldDbStatus.pathEmpty:
        return 'Δεν έχει οριστεί διαδρομή βάσης προς ανάγνωση.';
      case LampOldDbStatus.pendingCreation:
        return _pendingCreationMessageGreek();
      case LampOldDbStatus.invalidPathFormat:
        return technicalDetail ??
            'Η διαδρομή πρέπει να δείχνει σε αρχείο με κατάληξη .db';
      case LampOldDbStatus.fileMissing:
        return 'Το αρχείο βάσης δεν βρέθηκε στη δίσκο. Ελέγξτε τη διαδρομή (δίκτυο, αφαιρούμενο δίσκο).';
      case LampOldDbStatus.notAFile:
        return 'Η διαδρομή δεν δείχνει σε αρχείο. Ελέγξτε ότι είναι αρχείο .db.';
      case LampOldDbStatus.emptyFile:
        return 'Το αρχείο βάσης είναι άδειο (0 byte). Χρειάζεται έγκυρο αντίγραφο .db.';
      case LampOldDbStatus.openFailed:
        return 'Δεν ανοίγει ως βάση SQLite. Μπορεί να είναι κατεστραμμένο, κλειδωμένο ή άσχετο αρχείο. '
            '${technicalDetail != null ? "(λειτουργικό: $technicalDetail)" : ""}';
      case LampOldDbStatus.notOldEquipmentDb:
        if (technicalDetail != null && technicalDetail!.isNotEmpty) {
          return 'Η βάση ανοίγει αλλά η δομή του πίνακα equipment δεν ταιριάζει με βάση Λάμπας '
              '($technicalDetail). Βεβαιωθείτε ότι είναι εξαγόμενη από import Excel της Λάμπας.';
        }
        return 'Η βάση ανοίγει αλλά δεν φαίνεται «παλιά βάση εξοπλισμού Λάμπα» (λείπει αναμενόμενος πίνακας ή στήλες). '
            'Βεβαιωθείτε ότι είναι εξαγόμενη από import Excel της Λάμπας.';
      case LampOldDbStatus.ok:
        return 'Η βάση προς ανάγνωση είναι προσπελάσιμη και έγκυρη.';
      case LampOldDbStatus.outputPendingCreation:
        return 'Το αρχείο δεν υπάρχει ακόμα — θα δημιουργηθεί από το import.';
      case LampOldDbStatus.outputWillUpdate:
        return 'Η βάση είναι έγκυρη — θα διαγραφεί και θα ξαναδημιουργηθεί από το import.';
    }
  }

  String _pendingCreationMessageGreek() {
    final dbName = pendingDbFileName ?? '…';
    final folder = pendingFolderPath ?? '…';
    final excel = pendingExcelFileName?.trim();
    if (excel != null && excel.isNotEmpty) {
      return 'Το αρχείο [$dbName] θα δημιουργηθεί στον φάκελο [$folder] '
          'μετά την επιτυχή εισαγωγή του Excel [$excel] '
          '(κουμπί: $kLampExcelImportButtonLabel).';
    }
    return 'Το αρχείο [$dbName] θα δημιουργηθεί στον φάκελο [$folder] '
        'όταν οριστεί αρχείο Excel και εκτελεστεί επιτυχώς η εισαγωγή '
        '(κουμπί: $kLampExcelImportButtonLabel).';
  }
}

/// True όταν ο έλεγχος εξόδου μπλοκάρει το κουμπί import Excel.
bool lampOutputPathBlocksImport(LampOldDbCheckResult result) {
  switch (result.status) {
    case LampOldDbStatus.pathEmpty:
    case LampOldDbStatus.outputPendingCreation:
    case LampOldDbStatus.outputWillUpdate:
      return false;
    case LampOldDbStatus.pendingCreation:
    case LampOldDbStatus.invalidPathFormat:
    case LampOldDbStatus.fileMissing:
    case LampOldDbStatus.notAFile:
    case LampOldDbStatus.emptyFile:
    case LampOldDbStatus.openFailed:
    case LampOldDbStatus.notOldEquipmentDb:
    case LampOldDbStatus.ok:
      return true;
  }
}

/// Επαλήθευση αρχείου για αναζήτηση/προβλήματα ETL (read path).
class LampOldDbValidator {
  LampOldDbValidator({LampDatabaseProvider? databaseProvider})
    : _databaseProvider = databaseProvider ?? LampDatabaseProvider.instance;

  final LampDatabaseProvider _databaseProvider;

  static const String _equipmentTable = 'equipment';

  /// Βασικές στήλες δακτυλικού αποτυπώματος πίνακα equipment Λάμπας.
  static const List<String> requiredEquipmentColumns = <String>[
    'code',
    'description',
    'model',
    'model_original_text',
    'owner',
    'office',
    'serial_no',
    'state',
  ];

  /// Έλεγχος μορφής διαδρομής .db (επικόλληση / χειροκίνητη εισαγωγή).
  /// Επιστρέφει `null` όταν η διαδρομή είναι κενή ή έγκυρη.
  static String? validateDbPathFormat(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final name = path.basename(trimmed);
    if (name.isEmpty) {
      return 'Η διαδρομή πρέπει να περιέχει όνομα αρχείου.';
    }
    if (!name.toLowerCase().endsWith('.db')) {
      return 'Η διαδρομή πρέπει να δείχνει σε αρχείο με κατάληξη .db';
    }
    if (name.contains(RegExp(r'[/\\]'))) {
      return 'Το όνομα αρχείου δεν πρέπει να περιέχει διαχωριστικά διαδρομής.';
    }
    return null;
  }

  static bool pathsReferToSameFile(String? a, String? b) {
    final ta = a?.trim() ?? '';
    final tb = b?.trim() ?? '';
    if (ta.isEmpty || tb.isEmpty) return false;
    final na = path.normalize(ta);
    final nb = path.normalize(tb);
    if (Platform.isWindows) {
      return na.toLowerCase() == nb.toLowerCase();
    }
    return na == nb;
  }

  /// Κλείνει τυχόν ανοιχτό handle της [LampDatabaseProvider] μετά τον έλεγχο
  /// ώστε αναζητήσεις να ξανα-ανοίγουν καθαρά.
  ///
  /// [outputPath] και [excelPath] χρησιμοποιούνται για ενημερωτικό μήνυμα όταν
  /// η ανάγνωση δείχνει στο μέλλον .db εξόδου που δεν έχει δημιουργηθεί ακόμα.
  Future<LampOldDbCheckResult> validateReadPath(
    String? rawPath, {
    String? outputPath,
    String? excelPath,
  }) async {
    final dbPath = rawPath?.trim() ?? '';
    if (dbPath.isEmpty) {
      return const LampOldDbCheckResult(LampOldDbStatus.pathEmpty);
    }

    final formatError = validateDbPathFormat(dbPath);
    if (formatError != null) {
      return LampOldDbCheckResult(
        LampOldDbStatus.invalidPathFormat,
        technicalDetail: formatError,
      );
    }

    final file = File(dbPath);
    try {
      if (!await file.exists()) {
        if (pathsReferToSameFile(dbPath, outputPath)) {
          final excelName = excelPath?.trim();
          return LampOldDbCheckResult(
            LampOldDbStatus.pendingCreation,
            pendingDbFileName: path.basename(dbPath),
            pendingFolderPath: path.dirname(dbPath),
            pendingExcelFileName: excelName == null || excelName.isEmpty
                ? null
                : path.basename(excelName),
          );
        }
        return const LampOldDbCheckResult(LampOldDbStatus.fileMissing);
      }
    } on FileSystemException catch (e) {
      return LampOldDbCheckResult(
        LampOldDbStatus.openFailed,
        technicalDetail: e.message,
      );
    }

    try {
      final type = (await file.stat()).type;
      if (type != FileSystemEntityType.file) {
        return const LampOldDbCheckResult(LampOldDbStatus.notAFile);
      }
    } on FileSystemException catch (e) {
      return LampOldDbCheckResult(
        LampOldDbStatus.openFailed,
        technicalDetail: e.message,
      );
    }

    try {
      final size = await file.length();
      if (size == 0) {
        return const LampOldDbCheckResult(LampOldDbStatus.emptyFile);
      }
    } on FileSystemException catch (e) {
      return LampOldDbCheckResult(
        LampOldDbStatus.openFailed,
        technicalDetail: e.message,
      );
    }

    return _openAndValidateLampEquipmentDb(dbPath);
  }

  /// Έλεγχος διαδρομής εξόδου (.db) για import Excel.
  Future<LampOldDbCheckResult> validateOutputPath(String? rawPath) async {
    final dbPath = rawPath?.trim() ?? '';
    if (dbPath.isEmpty) {
      return const LampOldDbCheckResult(LampOldDbStatus.pathEmpty);
    }

    final formatError = validateDbPathFormat(dbPath);
    if (formatError != null) {
      return LampOldDbCheckResult(
        LampOldDbStatus.invalidPathFormat,
        technicalDetail: formatError,
      );
    }

    final file = File(dbPath);
    try {
      if (!await file.exists()) {
        return const LampOldDbCheckResult(LampOldDbStatus.outputPendingCreation);
      }
    } on FileSystemException catch (e) {
      return LampOldDbCheckResult(
        LampOldDbStatus.openFailed,
        technicalDetail: e.message,
      );
    }

    try {
      final type = (await file.stat()).type;
      if (type != FileSystemEntityType.file) {
        return const LampOldDbCheckResult(LampOldDbStatus.notAFile);
      }
    } on FileSystemException catch (e) {
      return LampOldDbCheckResult(
        LampOldDbStatus.openFailed,
        technicalDetail: e.message,
      );
    }

    try {
      final size = await file.length();
      if (size == 0) {
        return const LampOldDbCheckResult(LampOldDbStatus.emptyFile);
      }
    } on FileSystemException catch (e) {
      return LampOldDbCheckResult(
        LampOldDbStatus.openFailed,
        technicalDetail: e.message,
      );
    }

    final result = await _openAndValidateLampEquipmentDb(dbPath);
    if (result.status == LampOldDbStatus.ok) {
      return const LampOldDbCheckResult(LampOldDbStatus.outputWillUpdate);
    }
    return result;
  }

  Future<LampOldDbCheckResult> _openAndValidateLampEquipmentDb(
    String dbPath,
  ) async {
    try {
      await _databaseProvider.close();
      final db = await _databaseProvider.open(
        dbPath,
        mode: LampDatabaseMode.read,
      );
      final rows = await db.rawQuery(
        "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = ? "
        "LIMIT 1",
        <Object?>[_equipmentTable],
      );
      if (rows.isEmpty) {
        await _databaseProvider.close();
        return const LampOldDbCheckResult(LampOldDbStatus.notOldEquipmentDb);
      }

      final structureError = await _validateEquipmentTableStructure(db);
      if (structureError != null) {
        await _databaseProvider.close();
        return LampOldDbCheckResult(
          LampOldDbStatus.notOldEquipmentDb,
          technicalDetail: structureError,
        );
      }

      await _databaseProvider.close();
      return const LampOldDbCheckResult(LampOldDbStatus.ok);
    } catch (e) {
      await _databaseProvider.close();
      return LampOldDbCheckResult(
        LampOldDbStatus.openFailed,
        technicalDetail: e.toString(),
      );
    }
  }

  /// Επιστρέφει ελληνικό μήνυμα με τις λείπουσες στήλες ή `null` αν είναι έγκυρη.
  Future<String?> _validateEquipmentTableStructure(Database db) async {
    final infoRows = await db.rawQuery('PRAGMA table_info($_equipmentTable)');
    final columnNames = infoRows
        .map((row) => (row['name'] as String?)?.trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    final missing = requiredEquipmentColumns
        .where((column) => !columnNames.contains(column))
        .toList();
    if (missing.isEmpty) {
      return null;
    }
    return 'λείπουν στήλες: ${missing.join(', ')}';
  }
}
