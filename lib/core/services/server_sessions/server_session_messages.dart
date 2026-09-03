/// Μετάφραση των ωμών κωδικών σφάλματος των Windows σε ελληνικά μηνύματα.
///
/// Οι αριθμοί και τα αίτια είναι **επιβεβαιωμένα ζωντανά** στους διακομιστές
/// 192.168.13.82/.83 (Windows Server 2003) — δεν είναι εικασίες από τεκμηρίωση.
/// Ζουν σε καθαρές συναρτήσεις ώστε να ελέγχονται χωρίς διακομιστή.
abstract final class ServerSessionMessages {
  ServerSessionMessages._();

  /// Άρνηση πρόσβασης.
  static const int errorAccessDenied = 5;

  /// Το δίκτυο δεν βρήκε τον διακομιστή.
  static const int errorBadNetpath = 53;

  /// Ο διακομιστής έκλεισε τη σύνδεση — το κλασικό σύμπτωμα «λείπει SMB1».
  static const int errorNetnameDeleted = 64;

  /// Δεν υπάρχει το κοινόχρηστο.
  static const int errorBadNetName = 67;

  /// Λάθος όνομα ή κωδικός.
  static const int errorLogonFailure = 1326;

  /// Ήδη ανοιχτή σύνδεση με άλλα στοιχεία.
  static const int errorSessionCredentialConflict = 1219;

  /// Ο κωδικός έληξε.
  static const int errorPasswordExpired = 1330;

  /// Ο λογαριασμός είναι απενεργοποιημένος.
  static const int errorAccountDisabled = 1331;

  /// Δεν επιτρέπεται δικτυακή σύνδεση σε αυτόν τον λογαριασμό.
  static const int errorLogonTypeNotGranted = 1385;

  /// Πρέπει να αλλάξει κωδικός πριν τη σύνδεση.
  static const int errorPasswordMustChange = 1907;

  /// Ο λογαριασμός είναι κλειδωμένος.
  static const int errorAccountLockedOut = 1909;

  /// Ο διακομιστής RPC δεν αποκρίνεται.
  static const int rpcServerUnavailable = 1722;

  /// Η συνεδρία δεν υπάρχει πια.
  static const int errorCtxWinstationNotFound = 7022;

  /// Δικός μας κωδικός: ο διακομιστής δέχτηκε την εντολή, αλλά η συνεδρία
  /// φαινόταν ακόμη ζωντανή στον αμέσως επόμενο έλεγχο.
  ///
  /// Αρνητικός επίτηδες — κανένας κωδικός των Windows δεν είναι αρνητικός,
  /// οπότε δεν μπορεί να συγκρουστεί με πραγματικό σφάλμα.
  static const int logoffNotVerified = -1;

  /// Η εξήγηση της **άρνησης πρόσβασης** (κωδικός 5), κοινή για κάθε ενέργεια.
  ///
  /// Ο κωδικός 5 δεν έρχεται ποτέ από αποτυχημένη σύνδεση: τη στιγμή που
  /// εμφανίζεται, ο διακομιστής μας έχει ήδη δεχτεί. Γι' αυτό δεν κατηγορεί
  /// τον λογαριασμό — μπορεί ο λογαριασμός να μην έχει καν ταξιδέψει. Οι τρεις
  /// αιτίες είναι μετρημένες στους 192.168.13.82/.83:
  ///  * ο λογαριασμός υπάρχει αλλά δεν είναι διαχειριστής ΕΚΕΙΝΟΥ του
  ///    διακομιστή — κάθε μηχάνημα έχει δικούς του λογαριασμούς·
  ///  * ο διακομιστής δεν αναγνώρισε τον λογαριασμό και υποβίβασε τη σύνδεση
  ///    σε επισκέπτη, οπότε η σύνδεση «πέτυχε» χωρίς κανένα δικαίωμα·
  ///  * ο υπολογιστής μας έχει ήδη ανοιχτή σύνδεση προς τον ίδιο διακομιστή με
  ///    άλλα στοιχεία, και τα Windows κρατούν μία ταυτότητα ανά διακομιστή.
  ///
  /// Το [includePrinterRpcHint] προσθέτει την τέταρτη αιτία που ισχύει **μόνο**
  /// για τους εκτυπωτές. Σε άλλη ενέργεια θα ήταν λάθος ίχνος.
  static String accessDenied({
    required String what,
    required String host,
    required String account,
    bool includePrinterRpcHint = false,
  }) {
    final base =
        'Ο $host απέρριψε το αίτημα $what (άρνηση πρόσβασης). Η σύνδεση έγινε '
        'δεκτή, αλλά η εντολή δεν πέρασε ως διαχειριστής. Τρεις συνήθεις '
        'αιτίες: ο «$account» δεν είναι διαχειριστής ΤΟΥ ΔΙΑΚΟΜΙΣΤΗ $host — '
        'κάθε διακομιστής έχει δικούς του λογαριασμούς· ο $host δεν αναγνώρισε '
        'τον λογαριασμό και δέχτηκε τη σύνδεση ως επισκέπτη· ή αυτός ο '
        'υπολογιστής έχει ήδη ανοιχτή σύνδεση προς τον $host με άλλον '
        'λογαριασμό, π.χ. κοινόχρηστο φάκελο ή δίσκο δικτύου.';
    if (!includePrinterRpcHint) return base;
    return '$base Στους εκτυπωτές παίζει ρόλο και η ρύθμιση RPC αυτού του '
        'υπολογιστή: δες την κάρτα «Κατάσταση αυτού του υπολογιστή» στον '
        'Κατάλογο → Διάφορα → Διακομιστές.';
  }

  /// Μήνυμα για αποτυχία σύνδεσης δικτύου προς τον διακομιστή.
  static String forConnect({
    required int code,
    required String host,
    required String account,
  }) => switch (code) {
    errorLogonFailure =>
      'Λάθος όνομα ή κωδικός για τον λογαριασμό «$account» στον $host.',
    errorSessionCredentialConflict =>
      'Αυτός ο υπολογιστής έχει ήδη ανοιχτή σύνδεση προς τον $host με άλλον '
          'λογαριασμό. Χρειάζεται αποσύνδεση από τον διακομιστή ή επανεκκίνηση '
          'του υπολογιστή.',
    errorBadNetpath =>
      'Δεν βρέθηκε διαδρομή δικτύου προς τον $host. Είναι σωστή η διεύθυνση '
          'και ανοιχτός ο διακομιστής;',
    errorNetnameDeleted =>
      'Ο διακομιστής $host έκλεισε τη σύνδεση. Πιθανότερη αιτία: λείπει το '
          '«SMB 1.0/CIFS Client» από αυτόν τον υπολογιστή.',
    errorBadNetName => 'Δεν βρέθηκε το κοινόχρηστο IPC\$ στον $host.',
    errorAccountDisabled =>
      'Ο λογαριασμός «$account» είναι απενεργοποιημένος στον $host.',
    errorAccountLockedOut =>
      'Ο λογαριασμός «$account» είναι κλειδωμένος στον $host.',
    errorPasswordExpired || errorPasswordMustChange =>
      'Ο κωδικός του «$account» έχει λήξει και πρέπει να αλλάξει.',
    errorLogonTypeNotGranted =>
      'Ο λογαριασμός «$account» δεν επιτρέπεται να συνδεθεί δικτυακά στον $host.',
    rpcServerUnavailable =>
      'Ο διακομιστής $host δεν αποκρίνεται. Πιθανότερη αιτία: λείπει το '
          '«SMB 1.0/CIFS Client» από αυτόν τον υπολογιστή.',
    _ => 'Αποτυχία σύνδεσης με τον $host (κωδικός σφάλματος $code).',
  };

  /// Μήνυμα για αποτυχία ανάγνωσης της λίστας συνεδριών.
  static String forEnumerate({
    required int code,
    required String host,
    required String adminUser,
  }) => switch (code) {
    errorAccessDenied => accessDenied(
      what: 'ανάγνωσης συνεδριών',
      host: host,
      account: adminUser,
    ),
    rpcServerUnavailable =>
      'Ο διακομιστής $host δεν αποκρίνεται. Πιθανότερη αιτία: λείπει το '
          '«SMB 1.0/CIFS Client» από αυτόν τον υπολογιστή.',
    _ =>
      'Αδυναμία ανάγνωσης των συνεδριών του $host (κωδικός σφάλματος $code).',
  };

  /// Μήνυμα για αποτυχία τερματισμού συνεδρίας.
  static String forLogoff({
    required int code,
    required String host,
    required String adminUser,
  }) => switch (code) {
    errorAccessDenied => accessDenied(
      what: 'τερματισμού συνεδρίας',
      host: host,
      account: adminUser,
    ),
    errorCtxWinstationNotFound =>
      'Η συνεδρία δεν υπάρχει πια στον $host — πάτα «Ανανέωση» για να δεις την '
          'τρέχουσα εικόνα.',
    rpcServerUnavailable => 'Ο διακομιστής $host δεν αποκρίνεται.',
    logoffNotVerified =>
      'Ο $host δέχτηκε την εντολή, αλλά η συνεδρία φαινόταν ακόμη ενεργή αμέσως '
          'μετά. Πάτα «Ανανέωση» σε λίγα δευτερόλεπτα για να δεις αν έκλεισε.',
    _ => 'Αποτυχία τερματισμού συνεδρίας στον $host (κωδικός σφάλματος $code).',
  };

  /// Μήνυμα για αποτυχία αποσύνδεσης οθόνης.
  ///
  /// Ξεχωριστό από τον τερματισμό επίτηδες: ο χειριστής διάλεξε τη ΜΗ
  /// καταστροφική ενέργεια, και ένα μήνυμα που μιλά για «τερματισμό» θα τον
  /// έκανε να νομίζει ότι έκλεισε το medico κάποιου.
  static String forDisconnect({
    required int code,
    required String host,
    required String adminUser,
  }) => switch (code) {
    errorAccessDenied => accessDenied(
      what: 'αποσύνδεσης οθόνης',
      host: host,
      account: adminUser,
    ),
    errorCtxWinstationNotFound =>
      'Η συνεδρία δεν υπάρχει πια στον $host — πάτα «Ανανέωση» για να δεις την '
          'τρέχουσα εικόνα.',
    rpcServerUnavailable => 'Ο διακομιστής $host δεν αποκρίνεται.',
    _ =>
      'Αποτυχία αποσύνδεσης οθόνης στον $host (κωδικός σφάλματος $code). '
          'Η συνεδρία δεν πειράχτηκε.',
  };

  /// True όταν ο κωδικός δείχνει ότι φταίει το SMB1 του υπολογιστή μας.
  ///
  /// Το χρησιμοποιεί η οθόνη για να δείξει την οδηγία ενεργοποίησης δίπλα στο
  /// σφάλμα, αντί να αφήσει τον χειριστή να ψάχνει.
  static bool pointsToMissingSmb1(int code) =>
      code == errorNetnameDeleted || code == rpcServerUnavailable;
}
