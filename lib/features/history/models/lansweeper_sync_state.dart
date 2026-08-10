/// Η κατάσταση μιας κλήσης απέναντι στο Lansweeper.
///
/// Μοναδικό σημείο αλήθειας: εδώ ζει και ο κανόνας κανονικοποίησης («κενό ή
/// άγνωστο σημαίνει ακαταχώρητη») και οι ελληνικές ετικέτες. Πριν, ο κανόνας
/// ήταν γραμμένος μέσα σε αρχείο διεπαφής της αναφοράς και το ερώτημα προς τη
/// βάση τον αγνοούσε — δύο διατυπώσεις του ίδιου κανόνα αποκλίνουν σιωπηλά.
abstract final class LansweeperSyncState {
  static const String unsent = 'unsent';
  static const String sent = 'sent';
  static const String excluded = 'excluded';
  static const String failed = 'failed';

  /// Όλες οι καταστάσεις, με τη σειρά που εμφανίζονται στη διεπαφή.
  static const List<String> all = [unsent, sent, excluded, failed];

  /// Οι καταστάσεις που σημαίνουν «μένει να γίνει».
  ///
  /// Η αποτυχημένη ανήκει κι αυτή στην ουρά: θέλει ακριβώς την ίδια ενέργεια
  /// με την ακαταχώρητη. Αν έμενε απ' έξω, θα εξαφανιζόταν από τα μάτια του
  /// χρήστη ακριβώς όταν χρειάζεται προσοχή.
  static const List<String> queue = [unsent, failed];

  /// Κενό, `null` ή άγνωστη τιμή σημαίνει ακαταχώρητη.
  ///
  /// Στη βάση η στήλη είναι `NOT NULL DEFAULT 'unsent'`, οπότε το `null` έρχεται
  /// από τα μοντέλα και όχι από τις εγγραφές. Η άγνωστη τιμή πέφτει κι αυτή
  /// εδώ: κλήση που δεν ανήκει σε καμία κατηγορία θα ήταν αόρατη παντού.
  static String normalize(String? state) {
    final trimmed = (state ?? '').trim();
    if (trimmed.isEmpty) return unsent;
    return all.contains(trimmed) ? trimmed : unsent;
  }

  /// True όταν η κλήση περιμένει ακόμη καταχώρηση.
  static bool isQueued(String? state) => queue.contains(normalize(state));

  /// Ελληνική ετικέτα ενικού («Ακαταχώρητη»).
  static String label(String? state) => switch (normalize(state)) {
    sent => 'Καταχωρημένη',
    excluded => 'Εξαιρεμένη',
    failed => 'Αποτυχημένη',
    _ => 'Ακαταχώρητη',
  };

  /// Ελληνική ετικέτα πληθυντικού («Ακαταχώρητες») — για φίλτρα και μετρητές.
  static String labelPlural(String? state) => switch (normalize(state)) {
    sent => 'Καταχωρημένες',
    excluded => 'Εξαιρεμένες',
    failed => 'Αποτυχημένες',
    _ => 'Ακαταχώρητες',
  };
}
