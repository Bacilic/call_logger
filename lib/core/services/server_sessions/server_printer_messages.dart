/// Τα μηνύματα των εκτυπωτών, της ουράς εκτυπώσεων και της επανεκκίνησης.
///
/// Ζουν χωριστά από την υπηρεσία, όπως και τα μηνύματα των συνεδριών: είναι
/// καθαρές συναρτήσεις πάνω σε κωδικούς σφάλματος, οπότε ελέγχονται χωρίς
/// διακομιστή και χωρίς κλήσεις προς τα Windows.
library;

import 'server_session_messages.dart';

abstract final class ServerPrinterMessages {
  ServerPrinterMessages._();

  /// Δικός μας κωδικός: η ουρά εκτυπώσεων δεν σταμάτησε μέσα στο όριο χρόνου.
  ///
  /// Αρνητικός επίτηδες — κανένας κωδικός των Windows δεν είναι αρνητικός.
  static const int serviceStopTimedOut = -10;

  /// Δικός μας κωδικός: η ουρά σταμάτησε αλλά δεν ξαναξεκίνησε.
  static const int serviceStartTimedOut = -11;

  /// Ο εκτυπωτής δεν υπάρχει πια στον διακομιστή.
  static const int printerNotFound = 1801;

  /// Δεν βρέθηκε η υπηρεσία στον διακομιστή.
  static const int serviceNotFound = 1060;

  /// Ο διακομιστής τερματίζει ήδη.
  static const int shutdownInProgress = 1115;

  /// Δεν υπάρχει τερματισμός σε εξέλιξη για να ακυρωθεί.
  static const int noShutdownInProgress = 1116;

  /// Μήνυμα για ενέργεια πάνω σε εκτυπωτή ή ουρά.
  ///
  /// Το [staleShare] είναι **γεγονός, όχι υποψία**: μπαίνει true μόνο όταν τα
  /// Windows απάντησαν ρητά ότι η προηγούμενη σύνδεση προς τον διακομιστή δεν
  /// έκλεισε. Τότε η άρνηση πρόσβασης έχει ονομαστική αιτία, και το μήνυμα
  /// σταματά να απαριθμεί υποψίες.
  static String forPrinterAction({
    required int code,
    required String host,
    required String account,
    required String what,
    bool staleShare = false,
  }) => switch (code) {
    ServerSessionMessages.errorAccessDenied =>
      ServerSessionMessages.accessDenied(
        what: 'διαχείρισης εκτυπωτών',
        host: host,
        account: account,
        // Μόνο εδώ: η ρύθμιση RPC αφορά αποκλειστικά τους εκτυπωτές, και χωρίς
        // αυτήν η κλήση ταξιδεύει με την ταυτότητα του συνδεδεμένου χρήστη των
        // Windows αντί για τον λογαριασμό που άνοιξε η εφαρμογή.
        includePrinterRpcHint: true,
        staleShare: staleShare,
      ),
    ServerSessionMessages.rpcServerUnavailable =>
      'Ο διακομιστής $host δεν αποκρίνεται. Αν μόλις έγινε επανεκκίνηση της '
          'ουράς, δώσ\' του λίγα δευτερόλεπτα και πάτα «Ανανέωση».',
    printerNotFound =>
      'Ο εκτυπωτής δεν υπάρχει πια στον $host — πάτα «Ανανέωση» για την '
          'τρέχουσα εικόνα.',
    _ => 'Αποτυχία $what στον $host (κωδικός σφάλματος $code).',
  };

  /// Μήνυμα για ενέργεια πάνω στην ίδια την υπηρεσία της ουράς εκτυπώσεων.
  static String forSpoolerService({
    required int code,
    required String host,
    required String account,
    bool staleShare = false,
  }) => switch (code) {
    ServerSessionMessages.errorAccessDenied =>
      ServerSessionMessages.accessDenied(
        what: 'διαχείρισης της ουράς εκτυπώσεων',
        host: host,
        account: account,
        staleShare: staleShare,
      ),
    serviceStopTimedOut =>
      'Η ουρά εκτυπώσεων του $host δεν σταμάτησε εγκαίρως. Συνήθως φταίει '
          'κολλημένη εργασία ή οδηγός εκτυπωτή — δοκίμασε ξανά σε λίγο.',
    serviceStartTimedOut =>
      'Η ουρά εκτυπώσεων του $host σταμάτησε αλλά ΔΕΝ ξαναξεκίνησε. Χρειάζεται '
          'άμεσος έλεγχος: όσο είναι σταματημένη, κανείς δεν τυπώνει.',
    serviceNotFound => 'Δεν βρέθηκε υπηρεσία ουράς εκτυπώσεων στον $host.',
    ServerSessionMessages.rpcServerUnavailable =>
      'Ο διακομιστής $host δεν αποκρίνεται.',
    _ =>
      'Αποτυχία επανεκκίνησης της ουράς εκτυπώσεων στον $host '
          '(κωδικός σφάλματος $code).',
  };

  /// Μήνυμα για την επανεκκίνηση του ίδιου του διακομιστή.
  static String forRestart({
    required int code,
    required String host,
    required String account,
    bool staleShare = false,
  }) => switch (code) {
    ServerSessionMessages.errorAccessDenied =>
      ServerSessionMessages.accessDenied(
        what: 'επανεκκίνησης του διακομιστή',
        host: host,
        account: account,
        staleShare: staleShare,
      ),
    shutdownInProgress => 'Ο $host βρίσκεται ήδη σε διαδικασία τερματισμού.',
    noShutdownInProgress =>
      'Δεν υπάρχει επανεκκίνηση σε εξέλιξη στον $host — δεν υπήρχε τίποτα '
          'να ακυρωθεί.',
    ServerSessionMessages.rpcServerUnavailable =>
      'Ο διακομιστής $host δεν αποκρίνεται.',
    _ =>
      'Αποτυχία ενέργειας επανεκκίνησης στον $host (κωδικός σφάλματος $code).',
  };
}
