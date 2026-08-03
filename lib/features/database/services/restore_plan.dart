import 'package:path/path.dart' as p;

import 'database_zip_pick_restore.dart';

/// Επιλογές ονόματος στην επαναφορά από αντίγραφο `.zip`.
///
/// Συμβόλαιο: η επαναφορά γράφει πάντα στον φάκελο της τρέχουσας βάσης —
/// το αντίγραφο δεν γίνεται ποτέ χώρος λειτουργίας. Ο χρήστης επιλέγει μόνο
/// το όνομα του αρχείου προορισμού.
enum RestoreDestinationChoice {
  /// Αντικατάσταση της τρέχουσας ανοιχτής βάσης (κρατά το τρέχον όνομα).
  currentDatabase,

  /// Νέο αρχείο στον φάκελο της τρέχουσας βάσης, με το όνομα του αντιγράφου.
  backupName;

  /// Προεπιλογή: η λέξη «επαναφορά» σημαίνει αντικατάσταση της τρέχουσας.
  static const defaultChoice = RestoreDestinationChoice.currentDatabase;
}

/// Τελική απόλυτη διαδρομή για την επιλογή ονόματος.
String resolveRestoreTargetPath({
  required RestoreDestinationChoice choice,
  required String currentDatabasePath,
  String? backupDatabaseFileName,
}) {
  switch (choice) {
    case RestoreDestinationChoice.currentDatabase:
      return currentDatabasePath;
    case RestoreDestinationChoice.backupName:
      final name =
          DatabaseZipPickRestore.usableDatabaseFileName(
            backupDatabaseFileName,
          ) ??
          DatabaseZipPickRestore.restoredDatabaseFileName;
      return p.join(p.dirname(currentDatabasePath), name);
  }
}

/// Ποιες επιλογές ονόματος είναι διαθέσιμες.
///
/// Το όνομα του αντιγράφου προσφέρεται μόνο όταν είναι αξιοποιήσιμο και
/// διαφέρει από το τρέχον — αλλιώς οι δύο επιλογές ταυτίζονται.
List<RestoreDestinationChoice> availableRestoreDestinations({
  required String currentDatabasePath,
  String? backupDatabaseFileName,
}) {
  final name = DatabaseZipPickRestore.usableDatabaseFileName(
    backupDatabaseFileName,
  );
  if (name == null) {
    return const [RestoreDestinationChoice.currentDatabase];
  }
  final currentName = p.basename(currentDatabasePath);
  if (name.toLowerCase() == currentName.toLowerCase()) {
    return const [RestoreDestinationChoice.currentDatabase];
  }
  return const [
    RestoreDestinationChoice.currentDatabase,
    RestoreDestinationChoice.backupName,
  ];
}
