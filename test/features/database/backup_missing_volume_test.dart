// Η εφαρμογή δεν προτείνει δημιουργία φακέλου σε δίσκο που δεν υπάρχει.
//
// Το συμβόλαιο: «Η εφαρμογή δεν προσφέρει δημιουργία φακέλου σε τόμο που δεν
// υπάρχει — και όταν η δημιουργία αποτύχει, λέει γιατί.»
//
// Πριν: με διαδρομή σε ανύπαρκτο δίσκο (π.χ. «k:\...») ο διάλογος ρωτούσε «να
// δημιουργηθεί;», η δημιουργία αποτύγχανε, και η αιτία σβηνόταν από ένα
// γενικό «ο φάκελος δεν υπάρχει» — έτσι έμοιαζε σαν να μην έγινε τίποτα.
//
//   flutter test test/features/database/backup_missing_volume_test.dart

import 'dart:io';

import 'package:call_logger/features/database/utils/backup_location_hints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ύπαρξη τόμου διαδρομής', () {
    test('υπαρκτός δίσκος: ναι', () {
      // Ο δίσκος του τρέχοντος φακέλου υπάρχει εξ ορισμού.
      expect(
        BackupLocationHints.volumeOfPathExists(Directory.current.path),
        isTrue,
      );
    });

    test('γράμμα δίσκου που δεν υπάρχει: όχι', () {
      // Μόνο σε Windows: αλλού η έννοια του γράμματος τόμου δεν υπάρχει.
      if (!Platform.isWindows) return;
      expect(BackupLocationHints.volumeOfPathExists(r'K:\ανύπαρκτος'), isFalse);
    });

    test('διαδρομή χωρίς γράμμα τόμου (UNC): δεν κρίνεται ΕΔΩ', () {
      // Αυτός ο έλεγχος απαντά μόνο για γράμματα δίσκου, και το δηλώνει.
      // Τις δικτυακές διαδρομές τις κρίνει ο ασύγχρονος έλεγχος
      // προσβασιμότητας — δες backup_destination_reachability_test.dart.
      // Όσο η απάντηση εδώ περνούσε για «ο προορισμός είναι εντάξει», ο
      // διάλογος πρόσφερε δημιουργία φακέλου σε άφταστο δίκτυο.
      expect(
        BackupLocationHints.volumeOfPathExists(r'\\server\share\backups'),
        isTrue,
      );
    });

    test('κενή διαδρομή δεν θεωρείται ανύπαρκτος τόμος', () {
      expect(BackupLocationHints.volumeOfPathExists(''), isTrue);
    });
  });

  group('Το γράμμα τόμου διαβάζεται σωστά', () {
    test('πεζό γράμμα ανεβαίνει σε κεφαλαίο', () {
      expect(BackupLocationHints.windowsDriveLetterFromPath(r'k:\a\b'), 'K');
    });

    test('UNC δεν έχει γράμμα', () {
      expect(
        BackupLocationHints.windowsDriveLetterFromPath(r'\\srv\share'),
        isNull,
      );
    });
  });
}
