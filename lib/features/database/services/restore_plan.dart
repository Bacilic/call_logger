import 'package:path/path.dart' as p;

import 'backup_zip_manifest.dart';
import 'database_zip_pick_restore.dart';

/// Επιλογές προορισμού επαναφοράς από αντίγραφο `.zip`.
enum RestoreDestinationChoice {
  /// Αντικατάσταση της τρέχουσας ανοιχτής βάσης.
  currentDatabase,

  /// Νέο αρχείο δίπλα στο `.zip` (μη καταστροφικό ως προς την τρέχουσα).
  besideZip,

  /// Αρχική διαδρομή όπως καταγράφηκε στο manifest του αντιγράφου.
  originalPathFromManifest;

  /// Προεπιλογή: η λέξη «επαναφορά» σημαίνει αντικατάσταση της τρέχουσας.
  static const defaultChoice = RestoreDestinationChoice.currentDatabase;
}

/// Τελική απόλυτη διαδρομή για την επιλογή προορισμού.
String resolveRestoreTargetPath({
  required RestoreDestinationChoice choice,
  required String currentDatabasePath,
  required String zipPath,
  BackupZipManifest? manifest,
  String? preferredDatabaseFileName,
}) {
  switch (choice) {
    case RestoreDestinationChoice.currentDatabase:
      return currentDatabasePath;
    case RestoreDestinationChoice.besideZip:
      return DatabaseZipPickRestore.targetDatabasePathFor(
        zipPath,
        preferredDatabaseFileName: preferredDatabaseFileName,
      );
    case RestoreDestinationChoice.originalPathFromManifest:
      final original = manifest?.originalDatabasePath?.trim() ?? '';
      if (original.isEmpty) {
        return currentDatabasePath;
      }
      return p.normalize(original);
  }
}

/// Ποιες επιλογές προορισμού είναι διαθέσιμες.
///
/// Η «αρχική διαδρομή» απαιτεί γνωστό manifest, διαφορετική διαδρομή από την
/// τρέχουσα, και εγγράψιμο φάκελο ([originalDirectoryWritable] υπολογίζεται
/// από τον καλούντα — αυτό το module δεν κάνει εργασίες δίσκου).
List<RestoreDestinationChoice> availableRestoreDestinations({
  required String currentDatabasePath,
  required String zipPath,
  required BackupZipManifest? manifest,
  required bool originalDirectoryWritable,
}) {
  final choices = <RestoreDestinationChoice>[
    RestoreDestinationChoice.currentDatabase,
    RestoreDestinationChoice.besideZip,
  ];

  final original = manifest?.originalDatabasePath?.trim() ?? '';
  if (manifest != null &&
      manifest.isKnown &&
      original.isNotEmpty &&
      originalDirectoryWritable) {
    final currentNorm = p.normalize(currentDatabasePath);
    final originalNorm = p.normalize(original);
    if (!_samePath(currentNorm, originalNorm)) {
      choices.add(RestoreDestinationChoice.originalPathFromManifest);
    }
  }
  return choices;
}

/// Ο διακόπτης «Άνοιγμα της βάσης που επαναφέρθηκε» έχει νόημα μόνο όταν
/// ο προορισμός δεν είναι ήδη η τρέχουσα βάση.
bool restoreOpenSwitchMeaningful(RestoreDestinationChoice choice) =>
    choice != RestoreDestinationChoice.currentDatabase;

bool _samePath(String a, String b) {
  final na = p.normalize(a).replaceAll('/', '\\').toLowerCase();
  final nb = p.normalize(b).replaceAll('/', '\\').toLowerCase();
  return na == nb;
}
