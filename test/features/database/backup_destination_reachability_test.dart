// Μπορεί να δημιουργηθεί φάκελος αντιγράφων εκεί; Ένας κριτής, όλες οι μορφές
// διαδρομής.
//
// Το συμβόλαιο: «Κανένας διάλογος δεν προσφέρει ενέργεια που η εφαρμογή ήδη
// ξέρει ότι θα αποτύχει.»
//
// Πριν, ο έλεγχος κοίταζε μόνο γράμματα δίσκου: για δικτυακή διαδρομή
// απαντούσε πάντα «εντάξει», οπότε σε μηχάνημα εκτός του δικτύου του
// νοσοκομείου ο διάλογος πρόσφερε «Δημιουργία εδώ και εκτέλεση» — και το
// πάτημα οδηγούσε σε βέβαιη αποτυχία.
//
//   flutter test test/features/database/backup_destination_reachability_test.dart

import 'dart:io';

import 'package:call_logger/features/database/utils/backup_destination_reachability.dart';
import 'package:flutter_test/flutter_test.dart';

/// Το πραγματικό σενάριο του Διευθυντή.
const _hospitalShare =
    r'\\gnk.local\Departments\TPO\Utilities\Call Logger\Backups';

void main() {
  group('Η ρίζα του κοινόχρηστου', () {
    test('βγαίνει από δικτυακή διαδρομή', () {
      expect(uncShareRoot(_hospitalShare), r'\\gnk.local\Departments');
    });

    test('δέχεται και κάθετες προς τα εμπρός', () {
      expect(uncShareRoot('//srv/share/a/b'), r'\\srv\share');
    });

    test('τοπική διαδρομή δεν έχει ρίζα κοινόχρηστου', () {
      expect(uncShareRoot(r'F:\backups'), isNull);
      expect(uncShareRoot('/home/user/backups'), isNull);
    });

    test('μισοτελειωμένη δικτυακή διαδρομή δεν κρίνεται', () {
      // Μόνο ο διακομιστής, χωρίς κοινόχρηστο: δεν υπάρχει ρίζα να ελεγχθεί.
      expect(uncShareRoot(r'\\srv'), isNull);
    });
  });

  group('Ο έλεγχος προσβασιμότητας', () {
    test('δικτυακός φάκελος που δεν απαντά: ΔΕΝ δημιουργείται', () async {
      final reach = await probeBackupDestinationReachability(
        _hospitalShare,
        probeDirectoryExists: (_) async => false,
      );
      expect(reach, BackupDestinationReachability.networkUnreachable);
      expect(
        reach.canCreateFolder,
        isFalse,
        reason:
            'Εδώ ακριβώς εμφανιζόταν το «Δημιουργία εδώ και εκτέλεση» που '
            'οδηγούσε σε βέβαιη αποτυχία.',
      );
    });

    test('δικτυακός φάκελος που αργεί: μετράει ως άφταστος', () async {
      final reach = await probeBackupDestinationReachability(
        _hospitalShare,
        timeout: const Duration(milliseconds: 40),
        probeDirectoryExists: (_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return true;
        },
      );
      expect(
        reach,
        BackupDestinationReachability.networkUnreachable,
        reason:
            'Ένα άφταστο δίκτυο απαντά μετά από δευτερόλεπτα· ο διάλογος δεν '
            'επιτρέπεται να περιμένει τόσο.',
      );
    });

    test('δικτυακός φάκελος που απαντά: δημιουργείται', () async {
      final reach = await probeBackupDestinationReachability(
        _hospitalShare,
        probeDirectoryExists: (_) async => true,
      );
      expect(reach, BackupDestinationReachability.creatable);
    });

    test('ο έλεγχος ρωτά τη ΡΙΖΑ, όχι ολόκληρη τη διαδρομή', () async {
      String? asked;
      await probeBackupDestinationReachability(
        _hospitalShare,
        probeDirectoryExists: (path) async {
          asked = path;
          return true;
        },
      );
      expect(
        asked,
        r'\\gnk.local\Departments',
        reason:
            'Οι ενδιάμεσοι φάκελοι μπορεί να λείπουν και να είναι '
            'δημιουργήσιμοι· ο κοινόχρηστος όχι.',
      );
    });

    test('γράμμα δίσκου που δεν υπάρχει: ΔΕΝ δημιουργείται', () async {
      if (!Platform.isWindows) return;
      final reach = await probeBackupDestinationReachability(
        r'K:\ανύπαρκτος',
      );
      expect(reach, BackupDestinationReachability.volumeMissing);
      expect(reach.canCreateFolder, isFalse);
    });

    test('υπαρκτός τοπικός δίσκος: δημιουργείται', () async {
      final reach = await probeBackupDestinationReachability(
        Directory.current.path,
      );
      expect(reach, BackupDestinationReachability.creatable);
    });

    test('κενή διαδρομή δεν αποκλείεται εδώ', () async {
      // Έχει δικό της μήνυμα («δεν έχει οριστεί φάκελος») — δεν είναι δουλειά
      // αυτού του ελέγχου να το πει.
      final reach = await probeBackupDestinationReachability('   ');
      expect(reach, BackupDestinationReachability.creatable);
    });

    test('το δίκτυο δεν ερωτάται καθόλου για τοπική διαδρομή', () async {
      var asked = false;
      await probeBackupDestinationReachability(
        Directory.current.path,
        probeDirectoryExists: (_) async {
          asked = true;
          return true;
        },
      );
      expect(
        asked,
        isFalse,
        reason:
            'Ένας τοπικός δίσκος απαντά αμέσως· δεν πληρώνει την αναμονή του '
            'δικτύου.',
      );
    });
  });
}
