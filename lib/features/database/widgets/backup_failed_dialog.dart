import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart';
import '../providers/database_backup_settings_provider.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_destination_reachability.dart';
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

  /// Φτιάχνει τον φάκελο που λείπει και τρέχει — προσφέρεται μόνο όταν ο
  /// προορισμός είναι προσβάσιμος.
  createAndRun,
}

/// Ποια ενέργεια έχει νόημα να προταθεί ως **κύρια**, με βάση το τι βρήκε ο
/// ζωντανός έλεγχος.
///
/// Καθαρή απόφαση, έξω από το widget, ώστε να ελέγχεται χωρίς οθόνη. Ο κανόνας
/// είναι ένας: **ποτέ ενέργεια που ξέρουμε ότι θα αποτύχει.** Το «Εκτέλεση
/// τώρα» ξαναδοκιμάζει ό,τι μόλις απέτυχε· έχει νόημα μόνο όταν ο φάκελος
/// είναι εντάξει και η αιτία ήταν αλλού.
BackupFailedChoice? primaryBackupFailedAction({
  required BackupDestinationValidationKind kind,
  required bool destinationCreatable,
}) {
  switch (kind) {
    case BackupDestinationValidationKind.ok:
      return BackupFailedChoice.runNow;
    case BackupDestinationValidationKind.missingDirectory:
      // Λείπει ο φάκελος: η επανάληψη ως έχει θα ξανα-αποτύχει. Αν ο
      // προορισμός είναι προσβάσιμος, η δημιουργία είναι η σωστή ενέργεια·
      // αλλιώς δεν υπάρχει καμία, και μένει μόνο η αλλαγή φακέλου.
      return destinationCreatable ? BackupFailedChoice.createAndRun : null;
    case BackupDestinationValidationKind.accessDenied:
    case BackupDestinationValidationKind.notADirectory:
    case BackupDestinationValidationKind.invalidPath:
      // Δικαιώματα, αρχείο αντί για φάκελο, άκυρη διαδρομή: τίποτα από όσα
      // μπορεί να κάνει η εφαρμογή δεν τα λύνει. Η αλλαγή φακέλου μένει
      // πάντα διαθέσιμη ως δεύτερο κουμπί.
      return null;
  }
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

/// Η επιπλέον πρόταση όταν ο φάκελος λείπει **και** ο προορισμός δεν είναι
/// προσβάσιμος: εκεί δεν υπάρχει καμία ενέργεια που να πετυχαίνει, και ο
/// χρήστης πρέπει να το ξέρει αντί να δοκιμάζει κουμπιά.
String backupUnreachableDestinationHint(BackupDestinationReachability reach) {
  return switch (reach) {
    BackupDestinationReachability.creatable => '',
    BackupDestinationReachability.networkUnreachable =>
      '\n\nΟ δικτυακός φάκελος δεν απαντά από αυτόν τον υπολογιστή, οπότε δεν '
          'μπορεί ούτε να δημιουργηθεί εκεί. Ορίστε άλλη διαδρομή.',
    BackupDestinationReachability.volumeMissing =>
      '\n\nΟ δίσκος της διαδρομής δεν είναι διαθέσιμος, οπότε ο φάκελος δεν '
          'μπορεί ούτε να δημιουργηθεί εκεί. Ορίστε άλλη διαδρομή.',
  };
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
  Future<BackupDestinationReachability> Function(String path)? probeReach,
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

  // Ρωτάμε ΚΑΙ αν ο προορισμός είναι προσβάσιμος: το «λείπει ο φάκελος» έχει
  // δύο πολύ διαφορετικές συνέχειες — «φτιάξ' τον» ή «δεν γίνεται τίποτα εδώ».
  final reach = await (probeReach ?? probeBackupDestinationReachability)(
    destination,
  );
  if (!context.mounted) return;

  final primary = primaryBackupFailedAction(
    kind: validation.kind,
    destinationCreatable: reach.canCreateFolder,
  );

  final explanation =
      backupFailureExplanation(
        destination: destination,
        kind: validation.kind,
      ) +
      (validation.kind == BackupDestinationValidationKind.missingDirectory
          ? backupUnreachableDestinationHint(reach)
          : '');

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
        // Χωρίς κύρια ενέργεια, η αλλαγή φακέλου ΕΙΝΑΙ η μόνη που οδηγεί
        // κάπου — και το δηλώνει παίρνοντας τη θέση του κύριου κουμπιού.
        if (primary == null)
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(BackupFailedChoice.changeFolder),
            child: const Text('Αλλαγή φακέλου'),
          )
        else ...[
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(BackupFailedChoice.changeFolder),
            child: const Text('Αλλαγή φακέλου'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(primary),
            child: Text(
              primary == BackupFailedChoice.createAndRun
                  ? 'Δημιουργία και εκτέλεση'
                  : 'Εκτέλεση τώρα',
            ),
          ),
        ],
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
    case BackupFailedChoice.createAndRun:
      await runBackupAndReport(context: context, ref: ref, createFolder: true);
  }
}
