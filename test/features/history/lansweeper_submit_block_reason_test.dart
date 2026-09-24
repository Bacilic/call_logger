// Γιατί κλειδώνει η Άμεση Καταχώρηση — μία απόφαση, για το κουμπί και για την υπόδειξη.
//
//   flutter test test/features/history/lansweeper_submit_block_reason_test.dart

import 'package:call_logger/features/history/models/lansweeper_connection_status.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_submit_block_reason.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? reasonWith({
    bool hasSelection = true,
    bool isRegistered = false,
    bool apiUrlValid = true,
    LansweeperConnectionStatus connection =
        const LansweeperConnectionAvailable(),
    bool busy = false,
  }) {
    return lansweeperImmediateSubmitBlockReason(
      hasSelection: hasSelection,
      isRegistered: isRegistered,
      apiUrlValid: apiUrlValid,
      connection: connection,
      busy: busy,
    );
  }

  group('λόγος κλειδώματος Άμεσης Καταχώρησης', () {
    test('με όλα εντάξει, τίποτα δεν εμποδίζει', () {
      expect(reasonWith(), isNull);
    });

    test('όσο τρέχει ο έλεγχος σύνδεσης, ΥΠΑΡΧΕΙ λόγος και λέγεται', () {
      // Αυτό ήταν το σφάλμα: το κουμπί κλείδωνε σε αυτή την κατάσταση και
      // καμία υπόδειξη δεν την κάλυπτε, οπότε ο χρήστης δεν είχε πώς να μάθει
      // γιατί δεν γινόταν τίποτα.
      final reason = reasonWith(
        connection: const LansweeperConnectionChecking(),
      );
      expect(reason, isNotNull);
      expect(reason, contains('έλεγχος σύνδεσης'));
    });

    test('όταν ο διακομιστής δεν απαντά, η αιτία φτάνει στον χρήστη', () {
      final reason = reasonWith(
        connection: const LansweeperConnectionUnavailable(
          'Λήξη χρόνου αναμονής',
        ),
      );
      expect(reason, contains('Λήξη χρόνου αναμονής'));
    });

    test('χωρίς επιλεγμένη κλήση, ο λόγος είναι η επιλογή', () {
      expect(reasonWith(hasSelection: false), contains('Επιλέξτε'));
    });

    test('καταχωρημένη κλήση δεν ξαναστέλνεται', () {
      expect(reasonWith(isRegistered: true), contains('ήδη καταχωρημένη'));
    });

    test('χωρίς έγκυρο URL API, ο λόγος δείχνει τις Ρυθμίσεις', () {
      expect(reasonWith(apiUrlValid: false), contains('Ρυθμίσεις'));
    });

    test('η απουσία επιλογής προηγείται κάθε άλλου λόγου', () {
      // Η σειρά βοηθά: πρώτα ό,τι διορθώνει ο χειριστής με ένα κλικ.
      final reason = reasonWith(
        hasSelection: false,
        apiUrlValid: false,
        connection: const LansweeperConnectionChecking(),
      );
      expect(reason, contains('Επιλέξτε'));
    });
  });

  group('λόγος από την κατάσταση σύνδεσης', () {
    test('διαθέσιμη σύνδεση δεν εμποδίζει', () {
      expect(
        lansweeperConnectionBlockReason(const LansweeperConnectionAvailable()),
        isNull,
      );
    });

    test('καμία κατάσταση εκτός της διαθέσιμης δεν μένει αμίλητη', () {
      for (final status in const <LansweeperConnectionStatus>[
        LansweeperConnectionChecking(),
        LansweeperConnectionUnavailable('οτιδήποτε'),
      ]) {
        expect(
          lansweeperConnectionBlockReason(status),
          isNotNull,
          reason: 'η κατάσταση $status κλειδώνει το κουμπί χωρίς εξήγηση',
        );
      }
    });
  });
}
