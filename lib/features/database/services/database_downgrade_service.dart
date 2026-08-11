import 'dart:io';

import '../../../core/database/schema_downgrade_compatibility.dart';
import 'database_upgrade_copy_service.dart';

// Η υποβάθμιση καθαυτή (έλεγχος + εγγραφή user_version) ζει στο
// core/database — «SQL μόνο στα Repositories». Εδώ μένει μόνο η
// ενορχήστρωση αρχείων (αντίγραφο), και το δημόσιο API επανεξάγεται
// ώστε οι καλούντες να μη χρειάζεται να ξέρουν τη διαίρεση.
export '../../../core/database/schema_downgrade_compatibility.dart'
    show DowngradeOutcome, downgradeDatabaseFileToAppVersion;

/// Δημιουργεί αντίγραφο «_υποβαθμισμένη_» και υποβαθμίζει ΕΚΕΙΝΟ.
///
/// Το πρωτότυπο μένει ανέγγιχτο για τη νεότερη εφαρμογή — έτσι σπάει και το
/// πινγκ-πονγκ: κάθε εφαρμογή δουλεύει στο δικό της αρχείο, καμία δεν
/// «διορθώνει» την έκδοση της άλλης.
Future<DowngradeOutcome> downgradeCopyToAppVersion(String sourceDbPath) async {
  final copy = await createUpgradeCopy(
    sourceDbPath,
    suffix: '_υποβαθμισμένη_',
  );
  if (!copy.isSuccess) {
    return DowngradeOutcome.failure(
      copy.errorMessage ?? 'Δεν δημιουργήθηκε αντίγραφο.',
    );
  }

  final outcome = await downgradeDatabaseFileToAppVersion(copy.copyPath!);
  if (!outcome.isSuccess) {
    // Μισοτελειωμένο αντίγραφο δεν μένει να μπερδεύει: αφαιρείται αθόρυβα.
    for (final suffix in const <String>['', '-wal', '-shm']) {
      try {
        final file = File('${copy.copyPath!}$suffix');
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
  return outcome;
}
