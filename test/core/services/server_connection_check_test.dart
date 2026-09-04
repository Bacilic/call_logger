// Ο «Έλεγχος σύνδεσης» της φόρμας διακομιστή.
//
// Το σφάλμα που γέννησε αυτά τα τεστ: ο έλεγχος ρωτούσε μόνο τις συνεδρίες και
// απαντούσε «ο διακομιστής απάντησε» ενώ οι εκτυπωτές του ίδιου διακομιστή
// ήταν νεκροί. Εδώ φυλάγεται ότι κάθε ικανότητα απαντά ΧΩΡΙΣΤΑ και ότι η μισή
// επιτυχία δεν περνά για ολόκληρη.
//
//   flutter test test/core/services/server_connection_check_test.dart

import 'package:call_logger/core/services/server_sessions/server_connection_check.dart';
import 'package:call_logger/core/services/server_sessions/server_printer_models.dart';
import 'package:call_logger/core/services/server_sessions/server_session_models.dart';
import 'package:flutter_test/flutter_test.dart';

ServerSession _session(int id) => ServerSession(
  sessionId: id,
  username: 'xrhsths$id',
  state: ServerSessionState.active,
);

ServerPrinter _printer(String name) => ServerPrinter(
  fullName: name,
  displayName: name,
  stationName: '',
  sessionId: null,
  driverName: '',
  statusFlags: 0,
  jobCount: 0,
);

void main() {
  group('Γραμμή συνεδριών', () {
    test('η επιτυχία μετρά τις συνεδρίες και δεν υπόσχεται ενέργειες', () {
      // Η αποσύνδεση οθόνης και ο τερματισμός ΔΕΝ δοκιμάζονται — μετρημένο
      // στον .83, όπου η λίστα διαβάζεται αλλά οι ενέργειες απορρίπτονται.
      final line = ServerConnectionChecker.lineForSessions(
        ServerSessionsResult.success([_session(1), _session(2)]),
      );

      expect(line.state, ServerCheckState.passed);
      expect(line.detail, contains('2'));
      expect(line.detail, contains('διαβάζεται'));
    });

    test('η αποτυχία κρατά το μήνυμα του διακομιστή', () {
      final line = ServerConnectionChecker.lineForSessions(
        const ServerSessionsResult.failure('Λάθος κωδικός'),
      );

      expect(line.state, ServerCheckState.failed);
      expect(line.detail, 'Λάθος κωδικός');
    });
  });

  group('Γραμμή εκτυπωτών', () {
    test('η περιορισμένη προβολή ΔΕΝ περνά για επιτυχία', () {
      // Το ακριβές σενάριο του 192.168.13.83.
      final line = ServerConnectionChecker.lineForPrinters(
        ServerPrintersResult.success(
          [_printer('a'), _printer('b')],
          source: PrinterSource.registry,
          fallbackCode: 1722,
        ),
      );

      expect(line.state, ServerCheckState.partial);
      expect(line.detail, contains('1722'));
      expect(line.detail, contains('ουρές όχι'));
    });

    test('η πλήρης προβολή είναι επιτυχία και λέει πόσοι', () {
      final line = ServerConnectionChecker.lineForPrinters(
        ServerPrintersResult.success([_printer('a')]),
      );

      expect(line.state, ServerCheckState.passed);
      expect(line.detail, contains('πλήρης'));
    });
  });

  group('Γραμμή διαχείρισης υπηρεσιών', () {
    test('το δικαίωμα δηλώνεται χωρίς να έχει γίνει επανεκκίνηση', () {
      final line = ServerConnectionChecker.lineForServiceControl(
        const ServerActionResult.success(),
      );

      expect(line.state, ServerCheckState.passed);
      expect(line.detail, contains('Επιτρέπεται'));
    });

    test('η άρνηση κρατά το μήνυμα', () {
      final line = ServerConnectionChecker.lineForServiceControl(
        const ServerActionResult.failure('Άρνηση πρόσβασης'),
      );

      expect(line.state, ServerCheckState.failed);
      expect(line.detail, 'Άρνηση πρόσβασης');
    });
  });

  group('Σειρά ελέγχων', () {
    test('και οι τρεις ικανότητες ελέγχονται, με σταθερή σειρά', () {
      expect(ServerConnectionChecker.order, [
        ServerCapability.sessions,
        ServerCapability.printers,
        ServerCapability.serviceControl,
      ]);
    });
  });
}
