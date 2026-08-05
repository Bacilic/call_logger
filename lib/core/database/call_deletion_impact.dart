/// Τι κρέμεται από **μία** κλήση.
class CallConnectionSummary {
  CallConnectionSummary({
    required this.callId,
    required this.date,
    required this.time,
    required List<String> taskTitles,
    required List<String> lansweeperTicketIds,
    required this.externalLinks,
  }) : taskTitles = List.unmodifiable(taskTitles),
       lansweeperTicketIds = List.unmodifiable(lansweeperTicketIds);

  final int callId;

  /// Ημερομηνία και ώρα όπως τις κρατά η βάση (`2026-08-03`, `09:40`).
  ///
  /// Αμετάφραστες: η μορφοποίηση για την οθόνη ανήκει στην παρουσίαση, εδώ
  /// χρειάζονται ταξινομήσιμες.
  final String date;
  final String time;

  /// Οι τίτλοι των ενεργών εκκρεμοτήτων που δείχνουν στην κλήση.
  final List<String> taskTitles;

  /// Οι διακριτοί αριθμοί εισιτηρίων Lansweeper, ταξινομημένοι.
  final List<String> lansweeperTicketIds;

  /// Εγγραφές του ιστορικού `call_external_links` αυτής της κλήσης.
  final int externalLinks;

  int get linkedTasks => taskTitles.length;

  bool get hasConnections => taskTitles.isNotEmpty || externalLinks > 0;
}

/// Τι κρέμεται από τις κλήσεις που πρόκειται να διαγραφούν.
///
/// Ζει ως **μία** τιμή και όχι ως σκόρπιοι μετρητές: κάθε διάλογος διαγραφής
/// μαθαίνει με μία ερώτηση όλα όσα θα χαθούν, οπότε όταν αύριο προστεθεί νέο
/// συνδεδεμένο δεδομένο μπαίνει εδώ και εμφανίζεται παντού — αντί να πρέπει να
/// το θυμηθεί ο καθένας χωριστά.
///
/// Τα αθροίσματα παράγονται από τις **ίδιες** περιλήψεις που βλέπει ο χρήστης,
/// ώστε η επικεφαλίδα να μην μπορεί ποτέ να διαφωνήσει με τη λίστα από κάτω.
class CallDeletionImpact {
  CallDeletionImpact(List<CallConnectionSummary> calls)
    : calls = List.unmodifiable(calls),
      connectedCalls = List.unmodifiable(
        calls.where((call) => call.hasConnections),
      ),
      taskTitles = List.unmodifiable([
        for (final call in calls) ...call.taskTitles,
      ]),
      externalLinks = calls.fold(0, (sum, call) => sum + call.externalLinks),
      lansweeperTicketIds = _distinctSortedTickets(calls);

  static final CallDeletionImpact empty = CallDeletionImpact(
    const <CallConnectionSummary>[],
  );

  /// Όλες οι κλήσεις της επιλογής, με ή χωρίς συνδέσεις.
  final List<CallConnectionSummary> calls;

  /// Μόνο όσες έχουν κάτι να δείξουν — αυτές απαριθμεί ο διάλογος.
  final List<CallConnectionSummary> connectedCalls;

  /// Οι τίτλοι όλων των συνδεδεμένων εκκρεμοτήτων.
  ///
  /// Τίτλοι και όχι σκέτο πλήθος: «2 συνδεδεμένες εκκρεμότητες» δεν λέει στον
  /// χρήστη τι θα συμπαρασύρει.
  final List<String> taskTitles;

  /// Εγγραφές του ιστορικού `call_external_links`.
  ///
  /// Χάνονται **μόνο** στην οριστική διαγραφή· η αναστρέψιμη τις αφήνει άθικτες.
  final int externalLinks;

  /// Οι διακριτοί αριθμοί εισιτηρίων Lansweeper όλης της επιλογής.
  final List<String> lansweeperTicketIds;

  int get linkedTasks => taskTitles.length;

  bool get hasLinkedTasks => taskTitles.isNotEmpty;

  bool get hasExternalLinks => externalLinks > 0;

  bool get hasConnections => hasLinkedTasks || hasExternalLinks;

  /// Πόσες συνδέσεις συνολικά — εκκρεμότητες και αιτήματα μαζί.
  int get totalConnections => linkedTasks + externalLinks;

  /// Πόσες κλήσεις χάνουν ιστορικό Lansweeper αν η διαγραφή γίνει οριστική.
  ///
  /// Πλήθος **κλήσεων** και όχι εγγραφών: η προειδοποίηση απαντά στο «σε πόσες
  /// από αυτές που διαγράφω», ενώ μια κλήση μπορεί να κρατά περισσότερες από
  /// μία εγγραφές ιστορικού.
  int get callsWithExternalLinks =>
      calls.where((call) => call.externalLinks > 0).length;

  static List<String> _distinctSortedTickets(
    List<CallConnectionSummary> calls,
  ) {
    final tickets = <String>{
      for (final call in calls) ...call.lansweeperTicketIds,
    };
    final sorted = tickets.toList()..sort(compareTicketIds);
    return List.unmodifiable(sorted);
  }
}

/// Αριθμητική σύγκριση όπου γίνεται, αλφαβητική αλλού: τα εισιτήρια Lansweeper
/// είναι συνήθως αριθμοί, οπότε το «5067, 5102, 5140» διαβάζεται σαν σειρά.
int compareTicketIds(String a, String b) {
  final na = int.tryParse(a);
  final nb = int.tryParse(b);
  if (na != null && nb != null) return na.compareTo(nb);
  return a.compareTo(b);
}
