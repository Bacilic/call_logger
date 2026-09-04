// Τα μηνύματα που βλέπει ο χειριστής όταν κάτι πάει στραβά με τον διακομιστή.
//
// Δεν ελέγχεται η διατύπωση αλλά η **ουσία**: ότι κάθε κωδικός σφάλματος
// οδηγεί στη σωστή αιτία και στη σωστή ενέργεια. Ένα μήνυμα που λέει «λάθος
// κωδικός» ενώ φταίει το SMB1 στέλνει τον χειριστή να αλλάζει κωδικούς επί
// μία ώρα.
//
//   flutter test test/core/services/server_session_messages_test.dart

import 'package:call_logger/core/services/server_sessions/server_session_messages.dart';
import 'package:call_logger/core/services/server_sessions/server_session_models.dart';
import 'package:call_logger/core/services/server_sessions/smb1_client_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Μηνύματα σύνδεσης', () {
    test('λάθος κωδικός ονομάζει τον λογαριασμό', () {
      final msg = ServerSessionMessages.forConnect(
        code: ServerSessionMessages.errorLogonFailure,
        host: '192.168.13.82',
        account: 'Administrator',
      );

      expect(msg, contains('Administrator'));
      expect(msg, contains('κωδικός'));
    });

    test('σφάλμα 64 δείχνει το SMB1, όχι τα διαπιστευτήρια', () {
      final msg = ServerSessionMessages.forConnect(
        code: ServerSessionMessages.errorNetnameDeleted,
        host: '192.168.13.82',
        account: 'Administrator',
      );

      expect(msg, contains('SMB 1.0/CIFS'));
      expect(msg.toLowerCase(), isNot(contains('λάθος όνομα')));
    });

    test('κλειδωμένος και ληγμένος λογαριασμός ξεχωρίζουν', () {
      final locked = ServerSessionMessages.forConnect(
        code: ServerSessionMessages.errorAccountLockedOut,
        host: 'x',
        account: 'a',
      );
      final expired = ServerSessionMessages.forConnect(
        code: ServerSessionMessages.errorPasswordExpired,
        host: 'x',
        account: 'a',
      );

      expect(locked, contains('κλειδωμένος'));
      expect(expired, contains('λήξει'));
      expect(locked, isNot(equals(expired)));
    });

    test('άγνωστος κωδικός αναφέρει τον αριθμό για διάγνωση', () {
      final msg = ServerSessionMessages.forConnect(
        code: 4321,
        host: 'x',
        account: 'a',
      );

      expect(msg, contains('4321'));
    });
  });

  group('Μηνύματα ανάγνωσης και τερματισμού', () {
    test('η αποτυχία ΑΝΑΓΝΩΣΗΣ δεν μιλά για τερματισμό', () {
      // Οι δύο ενέργειες μοιράζονται κωδικούς σφάλματος αλλά όχι μήνυμα:
      // «αποτυχία τερματισμού» σε μια απλή ανάγνωση θα έκανε τον χειριστή να
      // νομίζει ότι κάτι πείραξε στον διακομιστή.
      final msg = ServerSessionMessages.forEnumerate(
        code: ServerSessionMessages.errorAccessDenied,
        host: '192.168.13.82',
        adminUser: 'Administrator',
      );

      expect(msg, contains('ανάγνωσης'));
      expect(msg, isNot(contains('τερματισμ')));
    });

    test('άρνηση στον τερματισμό ζητά διαχειριστή ΤΟΥ ΔΙΑΚΟΜΙΣΤΗ', () {
      final msg = ServerSessionMessages.forLogoff(
        code: ServerSessionMessages.errorAccessDenied,
        host: '192.168.13.82',
        adminUser: 'Administrator',
      );

      expect(msg, contains('ΤΟΥ ΔΙΑΚΟΜΙΣΤΗ'));
    });

    test('συνεδρία που χάθηκε στο ενδιάμεσο ζητά Ανανέωση', () {
      final msg = ServerSessionMessages.forLogoff(
        code: ServerSessionMessages.errorCtxWinstationNotFound,
        host: 'x',
        adminUser: 'a',
      );

      expect(msg, contains('Ανανέωση'));
    });

    test('ανεπιβεβαίωτος τερματισμός δεν δηλώνεται ως αποτυχία εντολής', () {
      final msg = ServerSessionMessages.forLogoff(
        code: ServerSessionMessages.logoffNotVerified,
        host: '192.168.13.82',
        adminUser: 'Administrator',
      );

      expect(msg, contains('δέχτηκε την εντολή'));
      expect(msg, contains('Ανανέωση'));
    });

    test('η αποσύνδεση οθόνης ΔΕΝ μιλά για τερματισμό', () {
      // Ο χειριστής διάλεξε τη ΜΗ καταστροφική ενέργεια. Ένα μήνυμα που λέει
      // «τερματισμός» θα τον έκανε να νομίζει ότι έκλεισε το medico κάποιου.
      final msg = ServerSessionMessages.forDisconnect(
        code: ServerSessionMessages.errorAccessDenied,
        host: '192.168.13.82',
        adminUser: 'Administrator',
      );

      expect(msg, contains('αποσύνδεσης οθόνης'));
      expect(msg, isNot(contains('τερματισμ')));
    });

    test('άγνωστη αποτυχία αποσύνδεσης καθησυχάζει για τη συνεδρία', () {
      final msg = ServerSessionMessages.forDisconnect(
        code: 4321,
        host: 'x',
        adminUser: 'a',
      );

      expect(msg, contains('4321'));
      expect(msg, contains('δεν πειράχτηκε'));
    });

    test('ο δικός μας κωδικός δεν συγκρούεται με των Windows', () {
      expect(ServerSessionMessages.logoffNotVerified, lessThan(0));
    });
  });

  group('Ένδειξη SMB1', () {
    test('μόνο οι δύο κωδικοί που το προδίδουν', () {
      expect(
        ServerSessionMessages.pointsToMissingSmb1(
          ServerSessionMessages.errorNetnameDeleted,
        ),
        isTrue,
      );
      expect(
        ServerSessionMessages.pointsToMissingSmb1(
          ServerSessionMessages.rpcServerUnavailable,
        ),
        isTrue,
      );
      expect(
        ServerSessionMessages.pointsToMissingSmb1(
          ServerSessionMessages.errorLogonFailure,
        ),
        isFalse,
      );
    });

    test('η κατάσταση υπηρεσίας μεταφράζεται σωστά', () {
      expect(
        Smb1ClientCheck.statusFrom(state: kServiceRunning),
        Smb1ClientStatus.running,
      );
      expect(
        Smb1ClientCheck.statusFrom(state: 1),
        Smb1ClientStatus.installedNotRunning,
      );
      expect(
        Smb1ClientCheck.statusFrom(openError: kErrorServiceDoesNotExist),
        Smb1ClientStatus.missing,
      );
      expect(
        Smb1ClientCheck.statusFrom(openError: 5),
        Smb1ClientStatus.unknown,
      );
      expect(Smb1ClientCheck.statusFrom(), Smb1ClientStatus.unknown);
    });

    test('μόνο τα προβλήματα ζητούν ενέργεια από τον χειριστή', () {
      expect(Smb1ClientStatus.running.isProblem, isFalse);
      expect(Smb1ClientStatus.unknown.isProblem, isFalse);
      expect(Smb1ClientStatus.missing.isProblem, isTrue);
      expect(Smb1ClientStatus.installedNotRunning.isProblem, isTrue);
    });
  });

  group('Άρνηση πρόσβασης', () {
    test('δεν κατηγορεί μόνο τον λογαριασμό', () {
      // Ο κωδικός 5 έρχεται ΜΕΤΑ από επιτυχημένη σύνδεση: ο λογαριασμός μπορεί
      // να μην έχει καν ταξιδέψει. Ένα μήνυμα που δείχνει μόνο αυτόν στέλνει
      // τον χειριστή να ψάχνει κωδικούς για ένα πρόβλημα που είναι αλλού.
      final msg = ServerSessionMessages.forEnumerate(
        code: ServerSessionMessages.errorAccessDenied,
        host: '192.168.13.83',
        adminUser: 'Administrator',
      );

      expect(msg, contains('επισκέπτη'));
      expect(msg, contains('ήδη ανοιχτή σύνδεση'));
    });

    test('στους εκτυπωτές δείχνει και τη ρύθμιση RPC', () {
      final msg = ServerSessionMessages.accessDenied(
        what: 'διαχείρισης εκτυπωτών',
        host: '192.168.13.83',
        account: 'Administrator',
        includePrinterRpcHint: true,
      );

      expect(msg, contains('RPC'));
    });

    test('στις συνεδρίες ΔΕΝ μιλά για τη ρύθμιση RPC', () {
      // Η ρύθμιση αφορά μόνο τους εκτυπωτές. Σε άρνηση τερματισμού συνεδρίας
      // θα ήταν λάθος ίχνος.
      final msg = ServerSessionMessages.forLogoff(
        code: ServerSessionMessages.errorAccessDenied,
        host: '192.168.13.83',
        adminUser: 'Administrator',
      );

      expect(msg, isNot(contains('RPC')));
    });
  });

  group('Παλιά σύνδεση που δεν έκλεισε', () {
    test('μόνο τα «σε χρήση» μετρούν ως σύνδεση που επέζησε', () {
      // Το «δεν υπήρχε σύνδεση» είναι το ΦΥΣΙΟΛΟΓΙΚΟ αποτέλεσμα, όχι πρόβλημα:
      // αν μετρούσε, θα φωνάζαμε σε κάθε καθαρή εκκίνηση.
      expect(ServerSessionMessages.staleShareSurvived(0), isFalse);
      expect(
        ServerSessionMessages.staleShareSurvived(
          ServerSessionMessages.errorNotConnected,
        ),
        isFalse,
      );
      expect(
        ServerSessionMessages.staleShareSurvived(
          ServerSessionMessages.errorOpenFiles,
        ),
        isTrue,
      );
      expect(
        ServerSessionMessages.staleShareSurvived(
          ServerSessionMessages.errorDeviceInUse,
        ),
        isTrue,
      );
    });

    test('όταν επέζησε, η άρνηση το λέει ως γεγονός και όχι ως υποψία', () {
      final msg = ServerSessionMessages.accessDenied(
        what: 'τερματισμού συνεδρίας',
        host: '192.168.13.83',
        account: 'Administrator',
        staleShare: true,
      );

      expect(msg, contains('δεν ήταν δυνατόν να κλείσει'));
      expect(msg, isNot(contains('Τρεις συνήθεις αιτίες')));
    });

    test('χωρίς επιβίωση, το μήνυμα μένει ως έχει', () {
      final msg = ServerSessionMessages.accessDenied(
        what: 'τερματισμού συνεδρίας',
        host: '192.168.13.83',
        account: 'Administrator',
      );

      expect(msg, contains('Τρεις συνήθεις αιτίες'));
    });
  });

  group('Κατάσταση συνεδρίας', () {
    test('μόνο 0 και 4 μας ενδιαφέρουν', () {
      expect(serverSessionStateFromWts(0), ServerSessionState.active);
      expect(serverSessionStateFromWts(4), ServerSessionState.disconnected);
      expect(serverSessionStateFromWts(6), ServerSessionState.other);
    });

    test('συνεδρία χωρίς όνομα χρήστη δεν προσφέρεται για τερματισμό', () {
      const s = ServerSession(
        sessionId: 0,
        username: '   ',
        state: ServerSessionState.active,
      );

      expect(s.isLogoffCandidate, isFalse);
    });
  });
}
