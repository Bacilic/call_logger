import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqflite.dart';

import '../database_file_classifier.dart';
import 'lamp_database_provider.dart';

/// Αποτέλεσμα ελέγχου αρχείου .db «Λάμπα» για ανάγνωση (read path).
enum LampOldDbStatus {
  pathEmpty,

  /// Διαδρομή χωρίς κατάληξη .db ή άλλο σφάλμα μορφής (π.χ. επικόλληση φακέλου).
  invalidPathFormat,
  fileMissing,
  notAFile,
  emptyFile,
  openFailed,
  notOldEquipmentDb,
  ok,

  /// Το αρχείο είναι βάση της Καταγραφής Κλήσεων, όχι της Λάμπας.
  isCallLoggerDb,
}

class LampOldDbCheckResult {
  const LampOldDbCheckResult(this.status, {this.technicalDetail});

  final LampOldDbStatus status;
  final String? technicalDetail;

  String get userMessageGreek {
    switch (status) {
      case LampOldDbStatus.pathEmpty:
        return 'Δεν έχει οριστεί διαδρομή βάσης προς ανάγνωση.';
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
              '($technicalDetail). Βεβαιωθείτε ότι είναι η βάση της Λάμπας.';
        }
        return 'Η βάση ανοίγει αλλά δεν φαίνεται «παλιά βάση εξοπλισμού Λάμπα» (λείπει αναμενόμενος πίνακας ή στήλες). '
            'Βεβαιωθείτε ότι είναι η βάση της Λάμπας.';
      case LampOldDbStatus.ok:
        return 'Η βάση προς ανάγνωση είναι προσπελάσιμη και έγκυρη.';
      case LampOldDbStatus.isCallLoggerDb:
        final name = (technicalDetail != null && technicalDetail!.isNotEmpty)
            ? technicalDetail!
            : '…';
        return 'Το αρχείο «$name» είναι η βάση της Καταγραφής Κλήσεων, όχι της Λάμπας.';
    }
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
  Future<LampOldDbCheckResult> validateReadPath(String? rawPath) async {
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

  Future<LampOldDbCheckResult> _openAndValidateLampEquipmentDb(
    String dbPath,
  ) async {
    try {
      final kind = await classifyDatabaseFile(dbPath);
      if (kind == DatabaseFileKind.callLogger) {
        return LampOldDbCheckResult(
          LampOldDbStatus.isCallLoggerDb,
          technicalDetail: path.basename(dbPath),
        );
      }

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
