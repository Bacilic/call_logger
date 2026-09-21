import 'dart:io';

import 'package:call_logger/core/updates/update_package_contents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('απαγορευμένο περιεχόμενο πακέτου', () {
    test('φάκελος δεδομένων χρήστη κόβει το πακέτο', () {
      for (final prefix in updatePackageForbiddenPrefixes) {
        expect(
          () => assertNoUserDataEntries(['call_logger.exe', '$prefixκάτι.dat']),
          throwsA(isA<StateError>()),
          reason: 'Ο φάκελος «$prefix» δεν επιτρέπεται σε πακέτο ενημέρωσης.',
        );
      }
    });

    test('ο φάκελος πιάνεται και όταν κρύβεται πιο βαθιά', () {
      expect(
        () => assertNoUserDataEntries(const [
          'call_logger/data/flutter_assets/images/logo.png',
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('η ανάποδη κάθετος των Windows δεν ξεγελά τον έλεγχο', () {
      expect(
        () => assertNoUserDataEntries(const [r'Data Base\call_logger.db']),
        throwsA(isA<StateError>()),
      );
    });

    test('όνομα που απλώς ΜΟΙΑΖΕΙ με φάκελο περνά', () {
      assertNoUserDataEntries(const [
        'call_logger.exe',
        'images_readme.txt',
        'data/app.so',
      ]);
    });
  });

  // Ο κανόνας αξίζει μόνο αν τον ΡΩΤΟΥΝ και οι δύο πύλες. Έλεγχος πηγαίου
  // κώδικα και όχι συμπεριφοράς: το ζητούμενο είναι «ποιος κατέχει τη λίστα»,
  // δηλαδή δομή, όχι υπολογισμός.
  test('καμία πύλη δεν κρατά δικό της αντίγραφο της λίστας', () {
    const gates = [
      'lib/core/updates/update_installer_service.dart',
      'lib/features/database/debug/release_publisher_service.dart',
    ];
    for (final gate in gates) {
      final source = File(
        '${Directory.current.path}${Platform.pathSeparator}'
        '${gate.replaceAll('/', Platform.pathSeparator)}',
      ).readAsStringSync();
      expect(
        source.contains("'maps_images/'"),
        isFalse,
        reason:
            'Το «$gate» ξαναγράφει τη λίστα αντί να τη ρωτήσει — έτσι γεννιέται '
            'πακέτο που περνά τη μία πύλη και κόβεται στην άλλη.',
      );
      expect(
        source.contains('assertNoUserDataEntries'),
        isTrue,
        reason: 'Το «$gate» οφείλει να ρωτά τον κοινό κανόνα.',
      );
    }
  });
}
