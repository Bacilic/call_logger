// Τα μηνύματα των εκτυπωτών, της ουράς και της επανεκκίνησης.
//
// Το ζητούμενο δεν είναι η διατύπωση αλλά η **αιτία**: όταν η εφαρμογή ξέρει
// γιατί απορρίφθηκε το αίτημα — επειδή η παλιά σύνδεση προς τον διακομιστή δεν
// έκλεισε — το μήνυμα οφείλει να το λέει, αντί να απαριθμεί τρεις υποψίες και
// να στέλνει τον χειριστή να τις ψάξει μία μία.
//
//   flutter test test/core/services/server_printer_messages_test.dart

import 'package:call_logger/core/services/server_sessions/server_printer_messages.dart';
import 'package:call_logger/core/services/server_sessions/server_session_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const host = '192.168.13.83';
  const account = 'Administrator';

  group('Άρνηση πρόσβασης στους εκτυπωτές', () {
    test('με παλιά σύνδεση που επέζησε, ονομάζει την αιτία', () {
      final msg = ServerPrinterMessages.forPrinterAction(
        code: ServerSessionMessages.errorAccessDenied,
        host: host,
        account: account,
        what: 'ανάγνωσης εκτυπωτών',
        staleShare: true,
      );

      expect(msg, contains('δεν ήταν δυνατόν να κλείσει'));
      expect(msg, isNot(contains('Τρεις συνήθεις αιτίες')));
    });

    test('χωρίς παλιά σύνδεση, μένουν οι υποψίες και η υπόδειξη RPC', () {
      final msg = ServerPrinterMessages.forPrinterAction(
        code: ServerSessionMessages.errorAccessDenied,
        host: host,
        account: account,
        what: 'ανάγνωσης εκτυπωτών',
      );

      expect(msg, contains('Τρεις συνήθεις αιτίες'));
      expect(msg, contains('RPC'));
    });
  });

  group('Άρνηση πρόσβασης στην ουρά εκτυπώσεων', () {
    test('με παλιά σύνδεση που επέζησε, ονομάζει την αιτία', () {
      final msg = ServerPrinterMessages.forSpoolerService(
        code: ServerSessionMessages.errorAccessDenied,
        host: host,
        account: account,
        staleShare: true,
      );

      expect(msg, contains('δεν ήταν δυνατόν να κλείσει'));
      expect(msg, isNot(contains('Τρεις συνήθεις αιτίες')));
    });

    test('η υπόδειξη RPC δεν ξεφεύγει εδώ', () {
      // Η ρύθμιση RPC αφορά τους εκτυπωτές· στην ίδια την υπηρεσία θα ήταν
      // λάθος ίχνος.
      final msg = ServerPrinterMessages.forSpoolerService(
        code: ServerSessionMessages.errorAccessDenied,
        host: host,
        account: account,
      );

      expect(msg, isNot(contains('RPC')));
    });
  });

  group('Άρνηση πρόσβασης στην επανεκκίνηση του διακομιστή', () {
    test('με παλιά σύνδεση που επέζησε, ονομάζει την αιτία', () {
      final msg = ServerPrinterMessages.forRestart(
        code: ServerSessionMessages.errorAccessDenied,
        host: host,
        account: account,
        staleShare: true,
      );

      expect(msg, contains('δεν ήταν δυνατόν να κλείσει'));
      expect(msg, isNot(contains('Τρεις συνήθεις αιτίες')));
    });
  });

  group('Το γεγονός δεν ξεχειλώνει σε άσχετους κωδικούς', () {
    test('ο εκτυπωτής που χάθηκε μένει «χάθηκε»', () {
      final msg = ServerPrinterMessages.forPrinterAction(
        code: ServerPrinterMessages.printerNotFound,
        host: host,
        account: account,
        what: 'εκκαθάρισης ουράς',
        staleShare: true,
      );

      expect(msg, contains('δεν υπάρχει πια'));
      expect(msg, isNot(contains('δεν ήταν δυνατόν να κλείσει')));
    });

    test('η ουρά που δεν ξαναξεκίνησε παραμένει το επείγον μήνυμα', () {
      final msg = ServerPrinterMessages.forSpoolerService(
        code: ServerPrinterMessages.serviceStartTimedOut,
        host: host,
        account: account,
        staleShare: true,
      );

      expect(msg, contains('ΔΕΝ ξαναξεκίνησε'));
      expect(msg, isNot(contains('δεν ήταν δυνατόν να κλείσει')));
    });

    test('η επανεκκίνηση που δεν υπήρχε δεν κατηγορεί σύνδεση', () {
      final msg = ServerPrinterMessages.forRestart(
        code: ServerPrinterMessages.noShutdownInProgress,
        host: host,
        account: account,
        staleShare: true,
      );

      expect(msg, contains('δεν υπήρχε τίποτα'));
      expect(msg, isNot(contains('δεν ήταν δυνατόν να κλείσει')));
    });
  });
}
