import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart';
import '../providers/database_backup_settings_provider.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_schedule_utils.dart';
import 'backup_destination_change_flow.dart';

/// Τι διάλεξε ο χρήστης στον διάλογο αποτυχίας.
enum BackupFailedChoice {
  /// Το αφήνει· η κατάσταση καθαρίζει ώστε να μην ξαναρωτηθεί για το ίδιο.
  ignore,

  /// Ορίζει άλλον φάκελο — η μόνη επιλογή που λύνει πραγματικά το πρόβλημα
  /// όταν η αποθηκευμένη διαδρομή δεν ισχύει πια.
  changeFolder,

  /// Ξαναδοκιμάζει ως έχει.
  runNow,
}

/// Τι λέμε στον χρήστη για την αποτυχία, με βάση τον **ζωντανό** έλεγχο του
/// φακέλου προορισμού.
///
/// Ο έλεγχος γίνεται τη στιγμή που ανοίγει ο διάλογος και όχι με βάση το τι
/// είχε συμβεί τότε: ο χρήστης θέλει να ξέρει τι φταίει **τώρα** που κοιτάζει.
/// Και είναι έλεγχος που η εφαρμογή κάνει μόνη της — το παλιό «ελέγξτε τον
/// φάκελο προορισμού και τα δικαιώματα» ζητούσε από τον άνθρωπο μια δουλειά
/// που ήδη ξέρουμε να κάνουμε.
///
/// Καθαρή συνάρτηση, χωρίς widgets: το ίδιο κείμενο κρίνεται και από τα τεστ.
String backupFailureExplanation({
  required String destination,
  required BackupDestinationValidationKind kind,
}) {
  final dest = destination.trim();
  if (dest.isEmpty) {
    return 'Δεν έχει οριστεί φάκελος προορισμού, οπότε το αντίγραφο δεν έχει '
        'πού να γραφτεί.';
  }
  final reason = switch (kind) {
    BackupDestinationValidationKind.missingDirectory =>
      'Ο φάκελος δεν υπάρχει. Πιθανή αιτία: αποσυνδεδεμένος δίσκος, διαγραφή '
          'ή μετονομασία.',
    BackupDestinationValidationKind.accessDenied =>
      'Ο φάκελος υπάρχει, αλλά η εφαρμογή δεν έχει δικαίωμα εγγραφής σε αυτόν.',
    BackupDestinationValidationKind.notADirectory =>
      'Η διαδρομή δείχνει σε αρχείο, όχι σε φάκελο.',
    BackupDestinationValidationKind.invalidPath =>
      'Η διαδρομή δεν είναι έγκυρη.',
    // Ο φάκελος είναι μια χαρά — δεν εφευρίσκουμε αιτία που δεν ξέρουμε.
    BackupDestinationValidationKind.ok =>
      'Ο φάκελος είναι προσβάσιμος και εγγράψιμος, οπότε η αποτυχία οφείλεται '
          'σε κάτι άλλο. Η «Εκτέλεση τώρα» θα δείξει το ακριβές σφάλμα.',
  };
  return 'Φάκελος προορισμού:\n$dest\n\n$reason';
}

/// Ο διάλογος που ανακοινώνει αποτυχία αυτόματου αντιγράφου.
///
/// Ζει σε δικό του αρχείο, δίπλα στον αδελφό του για τον φάκελο που λείπει:
/// όσο ήταν μέθοδος μέσα στο κέλυφος της εφαρμογής, το κέλυφος κουβαλούσε
/// ενορχήστρωση αντιγράφων που δεν του ανήκει.
Future<void> showBackupFailedDialog({
  required BuildContext context,
  required WidgetRef ref,
  Future<String?> Function()? pickFolder,
}) async {
  final settings = ref.read(databaseBackupSettingsProvider);
  final destination = settings.destinationDirectory.trim();

  // Οι ρυθμίσεις/ιστορικό αντιγράφων ζουν μέσα σε κάθε βάση — το μήνυμα
  // δηλώνει ρητά ποια βάση αφορά, αλλιώς μετά από αλλαγή βάσης ο χρήστης δεν
  // ξέρει για ποιο αρχείο μιλάμε.
  var dbScope = '';
  try {
    final db = await DatabaseHelper.instance.database;
    final base = p.basenameWithoutExtension(db.path).trim();
    if (base.isNotEmpty) dbScope = ' της βάσης «$base»';
  } catch (_) {}

  final validation = await BackupDestinationFolderValidator.validate(
    destination,
  );
  if (!context.mounted) return;

  final explanation = backupFailureExplanation(
    destination: destination,
    kind: validation.kind,
  );

  final choice = await showDialog<BackupFailedChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Αποτυχία Αντιγράφου Ασφαλείας'),
      content: SingleChildScrollView(
        child: Text(
          'Το αυτόματο αντίγραφο ασφαλείας$dbScope απέτυχε.\n\n$explanation',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(BackupFailedChoice.ignore),
          child: const Text('Παράβλεψη'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(BackupFailedChoice.changeFolder),
          child: const Text('Αλλαγή φακέλου'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(BackupFailedChoice.runNow),
          child: const Text('Εκτέλεση τώρα'),
        ),
      ],
    ),
  );

  if (!context.mounted) return;
  final notifier = ref.read(databaseBackupSettingsProvider.notifier);

  switch (choice) {
    case null:
    case BackupFailedChoice.ignore:
      await notifier.setLastBackupStatus(BackupScheduleStatus.none);
    case BackupFailedChoice.changeFolder:
      await changeBackupFolderAndRun(
        context: context,
        ref: ref,
        pick: pickFolder,
      );
    case BackupFailedChoice.runNow:
      await runBackupAndReport(context: context, ref: ref, createFolder: false);
  }
}
