/// Η **μία** πύλη προς τον διακομιστή: άνοιγμα συνεδρίας SMB, η δουλειά, και
/// κλείσιμο ό,τι κι αν συμβεί.
///
/// Το κλείσιμο δεν είναι ευπρέπεια: μια ξεχασμένη ανοιχτή συνεδρία διαχειριστή
/// σε υπολογιστή γραφείου είναι διάπλατα ανοιχτή πόρτα προς τον διακομιστή.
/// Γι' αυτό ζει εδώ και όχι μέσα σε κάθε ροή — καμία νέα ροή δεν μπορεί να
/// ξεχάσει ούτε το κλείσιμο ούτε ό,τι άλλο μαθαίνουμε από τη σύνδεση.
///
/// Όλες οι κλήσεις **μπλοκάρουν** και γίνονται μέσα από `Isolate.run`.
library;

import 'server_session_messages.dart';
import 'windows_session_ffi.dart';

/// Το αποτέλεσμα μιας δουλειάς μαζί με το γεγονός που γεννά η ίδια η σύνδεση.
///
/// Το [staleShare] είναι ιδιότητα του **ανοίγματος**, κοινή για κάθε ενέργεια:
/// λέει ότι υπήρχε παλιά σύνδεση προς τον διακομιστή που δεν έκλεισε. Εξηγεί
/// μια άρνηση πρόσβασης που αλλιώς θα φαινόταν σφάλμα του λογαριασμού — η
/// εντολή ταξίδεψε με τα παλιά στοιχεία, γιατί τα Windows κρατούν μία ταυτότητα
/// ανά διακομιστή.
typedef WithAdminShare<T> = ({T result, bool staleShare});

abstract final class AdminShare {
  AdminShare._();

  /// Ανοίγει τη συνεδρία με τα στοιχεία διαχειριστή, τρέχει το [body], και
  /// κλείνει **πάντα**.
  ///
  /// Αν η σύνδεση δεν ανοίξει καθόλου, το [body] δεν εκτελείται ποτέ και το
  /// αποτέλεσμα το δίνει το [onConnectFailure] με τον κωδικό των Windows. Ο
  /// διαχωρισμός είναι ουσιώδης: «δεν μπήκαμε καν στον διακομιστή» και «μπήκαμε
  /// αλλά η ενέργεια απέτυχε» θέλουν εντελώς διαφορετικό μήνυμα.
  static WithAdminShare<T> run<T>({
    required String host,
    required String user,
    required String password,
    required T Function() body,
    required T Function(int code) onConnectFailure,
  }) {
    final rc = WindowsSessionFfi.connectIpcShare(
      host: host,
      user: user,
      password: password,
    );
    final staleShare = ServerSessionMessages.staleShareSurvived(
      rc.staleShareCode,
    );
    if (rc.code != 0) {
      WindowsSessionFfi.disconnectShare(host);
      return (result: onConnectFailure(rc.code), staleShare: staleShare);
    }
    try {
      return (result: body(), staleShare: staleShare);
    } finally {
      WindowsSessionFfi.disconnectShare(host);
    }
  }
}
