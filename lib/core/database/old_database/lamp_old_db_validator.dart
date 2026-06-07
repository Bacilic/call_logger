import 'dart:io';

import 'package:path/path.dart' as path;

import 'lamp_database_provider.dart';

/// Κουμπί import Excel στη Λάμπα — κοινό κείμενο σε μηνύματα pending creation.
const String kLampExcelImportButtonLabel =
    'Δημιουργία/ενημέρωση βάσης από Excel';

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
        return 'Η βάση ανοίγει αλλά δεν φαίνεται «παλιά βάση εξοπλισμού Λάμπα» (λείπει αναμενόμενος πίνακας). '
            'Βεβαιωθείτε ότι είναι εξοδαρισμένη από import Excel της Λάμπας.';
      case LampOldDbStatus.ok:
        return 'Η βάση προς ανάγνωση είναι προσπελάσιμη και έγκυρη.';
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

/// Επαλήθευση αρχείου για αναζήτηση/προβλήματα ETL (read path).
class LampOldDbValidator {
  LampOldDbValidator({LampDatabaseProvider? databaseProvider})
    : _databaseProvider = databaseProvider ?? LampDatabaseProvider.instance;

  final LampDatabaseProvider _databaseProvider;

  static const String _equipmentTable = 'equipment';

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
}
