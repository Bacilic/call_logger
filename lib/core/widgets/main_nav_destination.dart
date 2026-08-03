/// Λογικοί προορισμοί πλευρικής πλοήγησης (NavigationRail).
enum MainNavDestination {
  calls,
  tasks,
  directory,
  history,
  database,
  dictionary,
  lamp,

  /// Οθόνη debug σενάριων σφαλμάτων (μόνο kDebugMode desktop).
  debugScenarios;

  /// Η λεζάντα του κουμπιού στην πλευρική μπάρα.
  ///
  /// Μοναδική πηγή: τη διαβάζει και η σχεδίαση και ο υπολογισμός πλάτους της
  /// μπάρας, ώστε το πλάτος να ακολουθεί πάντα τα κείμενα που όντως φαίνονται.
  String get label => switch (this) {
    MainNavDestination.calls => 'Κλήσεις',
    MainNavDestination.tasks => 'Εκκρεμότητες',
    MainNavDestination.directory => 'Κατάλογος',
    MainNavDestination.history => 'Ιστορικό',
    MainNavDestination.database => 'Βάση Δεδομένων',
    MainNavDestination.dictionary => 'Λεξικό',
    MainNavDestination.lamp => 'Λάμπα',
    MainNavDestination.debugScenarios => 'Σενάρια',
  };
}

/// Λεζάντα του κουμπιού Ρυθμίσεων· δεν είναι προορισμός (ανοίγει δική του οθόνη),
/// αλλά μετράει το ίδιο για το πλάτος της μπάρας.
const String kMainNavSettingsLabel = 'Ρυθμίσεις';
