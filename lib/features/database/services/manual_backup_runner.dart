import '../../../core/database/backup_pending_changes.dart';
import '../../../core/database/database_helper.dart';
import '../models/database_backup_settings.dart';
import '../utils/backup_destination_folder_validator.dart';
import 'database_backup_audit.dart';
import 'database_backup_service.dart';

/// Τι πρέπει να κάνει η οθόνη μετά από «Δημιουργία αντιγράφου τώρα».
enum ManualBackupOutcome {
  /// Το αντίγραφο πάρθηκε — δείξε το [ManualBackupResult.message].
  success,

  /// Ο φάκελος προορισμού λείπει — άνοιξε τον διάλογο ανάκτησης.
  folderMissing,

  /// Το αρχείο γράφτηκε αλλά δεν άνοιξε στον έλεγχο, και σημαδεύτηκε ως
  /// χαλασμένο — ρώτα τον χρήστη αν θέλει να το σβήσει.
  ///
  /// Ξεχωριστή έκβαση από το [failure] γιατί υπάρχει **αρχείο στον δίσκο**:
  /// μια αποτυχία εγγραφής δεν αφήνει τίποτα για το οποίο να αποφασίσει
  /// κανείς, ενώ εδώ η απόφαση είναι δική του.
  verificationFailed,

  /// Απέτυχε για άλλο λόγο — δείξε το μήνυμα ως σφάλμα.
  failure,
}

/// Το αποτέλεσμα, χωρίς καμία γνώση διεπαφής.
class ManualBackupResult {
  const ManualBackupResult(this.outcome, {this.message, this.brokenFilePath});

  final ManualBackupOutcome outcome;
  final String? message;

  /// Πού κατέληξε το σημαδεμένο αρχείο, όταν η έκβαση είναι
  /// [ManualBackupOutcome.verificationFailed].
  final String? brokenFilePath;
}

/// Παίρνει χειροκίνητο αντίγραφο και **προχωρά το σημάδι των αλλαγών**.
///
/// Το τελευταίο δεν είναι λεπτομέρεια: χωρίς αυτό, ο χρονιστής θα ξανάπαιρνε
/// αντίγραφο για τις ίδιες αλλαγές που μόλις φυλάχτηκαν. Γι' αυτό η δουλειά
/// ζει εδώ και όχι μέσα στο κουμπί — ένας μελλοντικός δεύτερος καλών δεν
/// μπορεί να ξεχάσει το βήμα.
///
/// Ο έλεγχος του φακέλου γίνεται **πριν** ξεκινήσει το αντίγραφο, ώστε ο
/// χρήστης να μη δει «αποτυχία» για κάτι που ήταν γνωστό εξαρχής.
Future<ManualBackupResult> runManualBackup({
  required DatabaseBackupSettings settings,
  required Future<BackupDestinationContentResult> Function() inspectDestination,
  required Future<void> Function({
    required int auditId,
    required DateTime at,
    required String? fullFingerprint,
    required DateTime? fullAt,
  })
  markBackupTaken,
}) async {
  final destination = settings.destinationDirectory.trim();
  if (destination.isNotEmpty) {
    final content = await inspectDestination();
    if (content.kind == BackupDestinationContentKind.folderMissing) {
      return const ManualBackupResult(ManualBackupOutcome.folderMissing);
    }
  }

  final result = await DatabaseBackupService.runBackup(
    settings,
    auditTrigger: BackupAuditTrigger.manual,
  );

  if (!result.success) {
    if (result.failureCode == DatabaseBackupFailureCode.folderMissing &&
        destination.isNotEmpty) {
      return const ManualBackupResult(ManualBackupOutcome.folderMissing);
    }
    if (result.isVerifiedBroken) {
      return ManualBackupResult(
        ManualBackupOutcome.verificationFailed,
        message: result.message,
        brokenFilePath: result.brokenArtifactPath,
      );
    }
    return ManualBackupResult(
      ManualBackupOutcome.failure,
      message: result.message ?? 'Αποτυχία αντιγράφου',
    );
  }

  final now = DateTime.now();
  final db = await DatabaseHelper.instance.database;
  final markId = await BackupPendingChangesRepository(db).latestAuditId();
  await markBackupTaken(
    auditId: markId,
    at: now,
    fullFingerprint: result.portableFingerprint,
    fullAt: result.isFullBackup ? now : null,
  );

  return ManualBackupResult(
    ManualBackupOutcome.success,
    message: result.outputPath != null
        ? 'Αντίγραφο: ${result.outputPath}'
        : (result.message ?? 'Επιτυχία'),
  );
}
