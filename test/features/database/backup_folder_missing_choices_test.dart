// Ο διάλογος «λείπει ο φάκελος αντιγράφων» δίνει και τρίτη διέξοδο.
//
// Το συμβόλαιο: «Όταν λείπει ο φάκελος προορισμού, ο χρήστης μπορεί πάντα να
// ορίσει ΑΛΛΗ διαδρομή — όχι μόνο να φτιάξει τον ίδιο ή να το αγνοήσει.»
//
// Γιατί μετράει: ο φάκελος μπορεί να λείπει επειδή η αποθηκευμένη διαδρομή δεν
// ισχύει πια (άλλη βάση, αλλαγμένος δικτυακός τόμος). Τότε η «δημιουργία»
// φτιάχνει άχρηστο φάκελο στο λάθος σημείο και τα αντίγραφα πάνε εκεί.
//
//   flutter test test/features/database/backup_folder_missing_choices_test.dart

import 'package:call_logger/features/database/widgets/backup_folder_missing_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Οι διέξοδοι του διαλόγου', () {
    test('υπάρχει επιλογή ορισμού ΑΛΛΗΣ διαδρομής', () {
      expect(
        BackupFolderMissingChoice.values,
        contains(BackupFolderMissingChoice.changeFolder),
        reason: 'Χωρίς αυτήν, η μόνη «λύση» ήταν να φτιαχτεί ο λάθος φάκελος.',
      );
    });

    test('οι τρεις διέξοδοι είναι διακριτές', () {
      expect(BackupFolderMissingChoice.values, hasLength(3));
      expect(BackupFolderMissingChoice.values.toSet(), hasLength(3));
    });

    test('η δημιουργία στην ίδια θέση ξεχωρίζει από την αλλαγή φακέλου', () {
      // Δύο πολύ διαφορετικές πράξεις: η μία κρατά τη διαδρομή, η άλλη την
      // αντικαθιστά. Ένα κοινό «ναι» θα τις μπέρδευε.
      expect(
        BackupFolderMissingChoice.createHere,
        isNot(BackupFolderMissingChoice.changeFolder),
      );
    });
  });
}
