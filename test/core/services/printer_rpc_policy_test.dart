// Η πολιτική «RPC εκτυπωτών»: τι λέει η κάρτα και τι περνά η εντολή.
//
// Ελέγχεται η **ουσία**, όχι η διατύπωση: ότι η μισοπερασμένη ρύθμιση
// ξεχωρίζει από την περασμένη και από την ανύπαρκτη (αλλιώς ο συνάδελφος
// βλέπει «εντάξει» ενώ η προβολή μένει περιορισμένη), και ότι η εντολή
// ανύψωσης περνά ΚΑΙ τις δύο τιμές με τους σωστούς αριθμούς — μια λάθος τιμή
// εκεί σημαίνει σφάλμα 1753 ή 5 στον διακομιστή.
//
//   flutter test test/core/services/printer_rpc_policy_test.dart

import 'package:call_logger/core/services/server_sessions/printer_rpc_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Κατάσταση της πολιτικής', () {
    test('και οι δύο τιμές περασμένες → πλήρης προβολή', () {
      const state = PrinterRpcPolicyState(
        namedPipeOk: true,
        authenticationOk: true,
        readable: true,
      );

      expect(state.status, PrinterRpcPolicyStatus.enabled);
      expect(state.status.isProblem, isFalse);
      expect(state.missingLabels, isEmpty);
    });

    test('μόνο η μία τιμή → μισοπερασμένη, ΟΧΙ εντάξει', () {
      const onlyPipe = PrinterRpcPolicyState(
        namedPipeOk: true,
        authenticationOk: false,
        readable: true,
      );
      const onlyAuth = PrinterRpcPolicyState(
        namedPipeOk: false,
        authenticationOk: true,
        readable: true,
      );

      expect(onlyPipe.status, PrinterRpcPolicyStatus.partial);
      expect(onlyAuth.status, PrinterRpcPolicyStatus.partial);
      expect(onlyPipe.status.isProblem, isTrue);
      expect(onlyAuth.status.isProblem, isTrue);
    });

    test('η μισοπερασμένη ονομάζει ΠΟΙΑ ρύθμιση λείπει', () {
      const onlyPipe = PrinterRpcPolicyState(
        namedPipeOk: true,
        authenticationOk: false,
        readable: true,
      );

      expect(onlyPipe.missingLabels, hasLength(1));
      expect(onlyPipe.label, contains(onlyPipe.missingLabels.first));
    });

    test('καμία τιμή → περιορισμένη προβολή', () {
      const state = PrinterRpcPolicyState(
        namedPipeOk: false,
        authenticationOk: false,
        readable: true,
      );

      expect(state.status, PrinterRpcPolicyStatus.disabled);
      expect(state.missingLabels, hasLength(2));
    });

    test('αδιάβαστο μητρώο δεν παριστάνει το «όλα καλά» ούτε το «χαλασμένο»', () {
      const state = PrinterRpcPolicyState.unreadable();

      expect(state.status, PrinterRpcPolicyStatus.unknown);
      // Το «άγνωστο» ΔΕΝ προσφέρει διόρθωση: δεν ξέρουμε αν χρειάζεται.
      expect(state.status.isProblem, isFalse);
    });
  });

  group('Εντολή ανύψωσης δικαιωμάτων', () {
    test('περνά και τις δύο τιμές με τους μετρημένους αριθμούς', () {
      final args = PrinterRpcPolicy.elevationArguments;

      expect(args, contains('${PrinterRpcPolicy.namedPipeValueName} '));
      expect(args, contains('${PrinterRpcPolicy.authenticationValueName} '));
      expect(args, contains('/d 1 '));
      expect(args, contains('/d 2 '));
      expect(args, contains(PrinterRpcPolicy.registryPath));
    });

    test('ένα μόνο παράθυρο ανύψωσης: οι δύο εγγραφές αλυσιδώνονται', () {
      final args = PrinterRpcPolicy.elevationArguments;

      expect('reg add'.allMatches(args).length, 2);
      expect(args, contains('&&'));
      expect(args, startsWith('/c '));
    });

    test('γράφει στον σωστό κλάδο του μητρώου', () {
      expect(
        PrinterRpcPolicy.elevationArguments,
        contains(r'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC'),
      );
    });
  });

  group('Εντολή επαναφοράς προεπιλογών', () {
    test('σβήνει ΜΟΝΟ τις δύο δικές μας τιμές, όχι το κλειδί', () {
      final args = PrinterRpcPolicy.restoreDefaultsArguments;

      expect('reg delete'.allMatches(args).length, 2);
      expect(args, contains('/v ${PrinterRpcPolicy.namedPipeValueName} '));
      expect(args, contains('/v ${PrinterRpcPolicy.authenticationValueName} '));
      // Μια διαγραφή χωρίς `/v` θα ξήλωνε ολόκληρο το κλειδί, παρασύροντας και
      // ρυθμίσεις που δεν βάλαμε εμείς — άρα κάθε `reg delete` πρέπει να έχει
      // το δικό του `/v`.
      expect('/v '.allMatches(args).length, 2);
    });

    test('μισοπερασμένη ρύθμιση: η απούσα τιμή δεν κόβει την αλυσίδα', () {
      final args = PrinterRpcPolicy.restoreDefaultsArguments;

      // Με `&&` η αποτυχία της πρώτης διαγραφής —απολύτως φυσιολογική όταν η
      // τιμή λείπει ήδη— θα ακύρωνε τη δεύτερη.
      expect(args, isNot(contains('&&')));
      expect(args, contains('&'));
      expect(args, endsWith('exit 0'));
    });

    test('η επαναφορά δείχνει στο ίδιο κλειδί με την ενεργοποίηση', () {
      expect(
        PrinterRpcPolicy.restoreDefaultsArguments,
        contains(r'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC'),
      );
    });
  });
}
