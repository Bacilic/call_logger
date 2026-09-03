// Το κείμενο της «περιορισμένης προβολής» εκτυπωτών.
//
// Κάτω από ένα μήνυμα κρύβονταν δύο εντελώς διαφορετικές αιτίες: ή λείπει η
// ρύθμιση RPC από ΑΥΤΟΝ τον υπολογιστή, ή η ρύθμιση είναι περασμένη και δεν
// απαντά η ουρά ΕΚΕΙΝΟΥ του διακομιστή. Το παλιό κείμενο έστελνε πάντα στη
// ρύθμιση — και με τη ρύθμιση ήδη περασμένη η οδηγία ήταν αδιέξοδη.
//
//   flutter test test/core/services/printer_limited_view_message_test.dart

import 'package:call_logger/core/services/server_sessions/printer_rpc_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const enabled = PrinterRpcPolicyState(
    namedPipeOk: true,
    authenticationOk: true,
    readable: true,
  );
  const disabled = PrinterRpcPolicyState(
    namedPipeOk: false,
    authenticationOk: false,
    readable: true,
  );
  const partial = PrinterRpcPolicyState(
    namedPipeOk: true,
    authenticationOk: false,
    readable: true,
  );

  group('Μήνυμα περιορισμένης προβολής εκτυπωτών', () {
    test('με τη ρύθμιση περασμένη δεν ζητά να ενεργοποιηθεί η ρύθμιση', () {
      // Το σενάριο που μετρήθηκε ζωντανά στον 192.168.13.83: η κάρτα δίπλα
      // έλεγε «πλήρης προβολή» ενώ ο διάλογος ζητούσε να ενεργοποιηθεί.
      final msg = enabled.limitedPrinterViewMessage(
        host: '192.168.13.83',
        showHint: true,
      );

      expect(msg, isNot(contains('ενεργοποιείται')));
      expect(msg, contains('192.168.13.83'));
      expect(msg, contains('Επανεκκίνηση ουράς εκτυπώσεων'));
    });

    test('όταν λείπει η ρύθμιση δείχνει πού ενεργοποιείται', () {
      final msg = disabled.limitedPrinterViewMessage(
        host: '192.168.13.83',
        showHint: true,
      );

      expect(msg, contains('Κατάσταση αυτού του υπολογιστή'));
    });

    test('η μισοπερασμένη ρύθμιση μετρά σαν να λείπει', () {
      final msg = partial.limitedPrinterViewMessage(
        host: '192.168.13.83',
        showHint: true,
      );

      expect(msg, contains('Κατάσταση αυτού του υπολογιστή'));
    });

    test('ο κωδικός των Windows φτάνει στην οθόνη', () {
      // Χωρίς αυτόν η περιορισμένη προβολή είναι «κάτι δεν πάει καλά» χωρίς
      // αιτία: 1753, 1722 και 1801 θέλουν τελείως διαφορετική κίνηση.
      final msg = enabled.limitedPrinterViewMessage(
        host: '192.168.13.83',
        showHint: true,
        errorCode: 1753,
      );

      expect(msg, contains('1753'));
    });

    test('χωρίς κωδικό δεν μπαίνει κενή παρένθεση', () {
      final msg = enabled.limitedPrinterViewMessage(
        host: '192.168.13.83',
        showHint: true,
      );

      expect(msg, isNot(contains('κωδικός')));
    });

    test(
      'μέσα στον ίδιο τον διάλογο επανεκκίνησης δεν προτείνει επανεκκίνηση',
      () {
        // Ο χειριστής είναι ΗΔΗ εκεί, με το κουμπί μπροστά του. Μια προτροπή να
        // πάει να το βρει στο μενού θα ήταν γελοία.
        final msg = enabled.limitedPrinterViewMessage(
          host: '192.168.13.83',
          showHint: true,
          suggestRestart: false,
        );

        expect(msg, isNot(contains('Δοκίμασε')));
        expect(msg, contains('192.168.13.83'));
        expect(msg, contains('σταματημένη'));
      },
    );

    test('ο διακόπτης της υπόδειξης γίνεται σεβαστός', () {
      // Προσωπική ρύθμιση: για όποιον θέλει απλώς να δει τους εκτυπωτές, η
      // υπόδειξη είναι θόρυβος. Ίσχυε μόνο στον έναν από τους δύο διαλόγους.
      final msg = disabled.limitedPrinterViewMessage(
        host: '192.168.13.83',
        showHint: false,
      );

      expect(msg, isNot(contains('Κατάσταση αυτού του υπολογιστή')));
      expect(msg, contains('Περιορισμένη προβολή'));
    });
  });
}
