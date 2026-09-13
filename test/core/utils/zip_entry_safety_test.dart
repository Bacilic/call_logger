// Ο κοινός κριτής διαδρομών αρχειοθήκης: τι γράφεται και τι παραλείπεται.
//
// Καθαρή λογική, χωρίς δίσκο — γι' αυτό εδώ ζουν οι παραλλαγές που θα ήταν
// ακριβές ή επικίνδυνες ως πραγματικές εγγραφές (απόλυτες διαδρομές, πολλά
// επίπεδα προς τα πάνω). Η άκρη-σε-άκρη συμπεριφορά ελέγχεται στο
// portable_restore_stays_inside_test.dart.
//
//   flutter test test/core/utils/zip_entry_safety_test.dart

import 'package:call_logger/core/utils/zip_entry_safety.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const root = r'C:\Εφαρμογή\maps_images';

  String? safePathOf(String entry) {
    final target = resolveZipEntryTarget(root: root, entryPath: entry);
    return switch (target) {
      SafeZipEntryTarget(:final absolutePath) => absolutePath,
      RejectedZipEntry() => null,
    };
  }

  String? rejectionOf(String entry) {
    final target = resolveZipEntryTarget(root: root, entryPath: entry);
    return switch (target) {
      RejectedZipEntry(:final reason) => reason,
      SafeZipEntryTarget() => null,
    };
  }

  group('ό,τι μένει μέσα, γράφεται', () {
    test('απλό όνομα αρχείου', () {
      expect(safePathOf('ισόγειο.png'), p.join(root, 'ισόγειο.png'));
    });

    test('υποφάκελος σε οποιοδήποτε βάθος', () {
      expect(
        safePathOf('κτίριο Α/όροφος 2/κάτοψη.png'),
        p.join(root, 'κτίριο Α', 'όροφος 2', 'κάτοψη.png'),
      );
    });

    test('ανάποδη κάθετος των Windows διαβάζεται κανονικά', () {
      expect(safePathOf(r'κτίριο Α\κάτοψη.png'), isNotNull);
    });

    test('«.» στη μέση δεν είναι διαφυγή', () {
      expect(safePathOf('κτίριο/./κάτοψη.png'), isNotNull);
    });

    test('«..» που επιστρέφει μέσα επιτρέπεται', () {
      // «κτίριο Α/../κτίριο Β/x.png» καταλήγει μέσα στο root. Ο κανόνας είναι
      // «πού καταλήγεις», όχι «ποια γράμματα έχεις».
      expect(
        safePathOf('κτίριο Α/../κτίριο Β/x.png'),
        p.join(root, 'κτίριο Β', 'x.png'),
      );
    });

    test('αρχείο με δύο τελείες στο όνομά του δεν μπερδεύεται με διαφυγή', () {
      // Ο παλιός έλεγχος του εγκαταστάτη απέρριπτε ΚΑΘΕ όνομα που περιείχε
      // «..», οπότε ένα «σχέδιο..τελικό.png» έκοβε ολόκληρο το πακέτο.
      expect(safePathOf('σχέδιο..τελικό.png'), isNotNull);
    });
  });

  group('ό,τι βγαίνει έξω, απορρίπτεται', () {
    test('ένα επίπεδο πάνω', () {
      expect(rejectionOf('../έξω.txt'), contains('έξω από τον φάκελο'));
    });

    test('πολλά επίπεδα πάνω', () {
      expect(rejectionOf('../../../../έξω.txt'), isNotNull);
    });

    test('διαφυγή μέσα από υποφάκελο', () {
      expect(rejectionOf('κτίριο/../../έξω.txt'), isNotNull);
    });

    test('η ίδια η ρίζα δεν είναι έγκυρος προορισμός', () {
      // Θα έγραφε ΠΑΝΩ στον φάκελο, όχι μέσα του.
      expect(rejectionOf('κτίριο/..'), isNotNull);
    });

    test('απόλυτη διαδρομή POSIX', () {
      expect(rejectionOf('/etc/κάτι'), contains('απόλυτη διαδρομή'));
    });

    test('απόλυτη διαδρομή με γράμμα δίσκου', () {
      expect(rejectionOf('C:/Windows/System32/κάτι.dll'), isNotNull);
      expect(rejectionOf(r'C:\Windows\κάτι.dll'), isNotNull);
    });

    test('γράμμα δίσκου χωρίς κάθετο είναι εξίσου έξω', () {
      // Στα Windows το «C:φάκελος» δείχνει στον τρέχοντα φάκελο ΕΚΕΙΝΟΥ του
      // δίσκου — όχι μέσα στον προορισμό μας.
      expect(rejectionOf('C:φάκελος/κάτι.txt'), isNotNull);
    });

    test('διαδρομή δικτύου', () {
      expect(rejectionOf(r'\\διακομιστής\κοινό\κάτι.txt'), isNotNull);
    });

    test('κενό όνομα', () {
      expect(rejectionOf('   '), contains('δεν έχει όνομα'));
    });
  });

  group('έλεγχος ολόκληρης αρχειοθήκης', () {
    test('καθαρή λίστα ονομάτων περνά', () {
      expect(
        firstEscapingEntryName(const [
          'app/call_logger.exe',
          'app/data/flutter_assets/AssetManifest.json',
        ]),
        isNull,
      );
    });

    test('επιστρέφει το ΠΡΩΤΟ ύποπτο όνομα, αυτούσιο', () {
      expect(
        firstEscapingEntryName(const [
          'app/call_logger.exe',
          'app/../../κακό.dll',
          'app/άλλο.dll',
        ]),
        'app/../../κακό.dll',
      );
    });

    test('άδεια λίστα δεν είναι πρόβλημα', () {
      expect(firstEscapingEntryName(const []), isNull);
    });
  });
}
