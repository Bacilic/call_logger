import 'dart:io';

import 'lamp_database_provider.dart';

/// Αποτέλεσμα ελέγχου αρχείου .db «Λάμπα» για ανάγνωση (read path).
enum LampOldDbStatus {
  pathEmpty,
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
  });

  final LampOldDbStatus status;
  final String? technicalDetail;

  String get userMessageGreek {
    switch (status) {
      case LampOldDbStatus.pathEmpty:
        return 'Δεν έχει οριστεί διαδρομή βάσης προς ανάγνωση. Ορίστε αρχείο .db στις ρυθμίσεις (γρανάζι).';
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
}

/// Επαλήθευση αρχείου για αναζήτηση/προβλήματα ETL (read path).
class LampOldDbValidator {
  LampOldDbValidator({LampDatabaseProvider? databaseProvider})
    : _databaseProvider = databaseProvider ?? LampDatabaseProvider.instance;

  final LampDatabaseProvider _databaseProvider;

  static const String _equipmentTable = 'equipment';

  /// Κλείνει τυχόν ανοιχτό handle της [LampDatabaseProvider] μετά τον έλεγχο
  /// ώστε αναζητήσεις να ξανα-ανοίγουν καθαρά.
  Future<LampOldDbCheckResult> validateReadPath(String? rawPath) async {
    final path = rawPath?.trim() ?? '';
    if (path.isEmpty) {
      return const LampOldDbCheckResult(LampOldDbStatus.pathEmpty);
    }

    final file = File(path);
    try {
      if (!await file.exists()) {
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
        path,
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
