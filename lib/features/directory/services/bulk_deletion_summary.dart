// Κοινή σύνοψη μαζικής διαγραφής — τμήματα, υπάλληλοι, εξοπλισμός.
//
// Καθαρή λογική χωρίς widgets: η γραμμή «τι ακριβώς αγγίζει η πράξη» χτίζεται
// με τον ίδιο τρόπο και στις τρεις οντότητες, ώστε ο χρήστης να μη μαθαίνει
// τρεις διαφορετικές μορφές για το ίδιο πράγμα.

/// Ένα σκέλος σύνοψης: πλήθος με ενικό και πληθυντικό.
class SummaryCount {
  const SummaryCount(this.count, this.singular, this.plural);

  final int count;

  /// Χωρίς τον αριθμό: «υπάλληλος», «κοινόχρηστο τηλέφωνο».
  final String singular;

  /// Χωρίς τον αριθμό: «υπάλληλοι», «κοινόχρηστα τηλέφωνα».
  final String plural;

  String get label => count == 1 ? '1 $singular' : '$count $plural';
}

/// Διαχωριστικό σκελών — μεσαία τελεία με κενά εκατέρωθεν.
const String kSummarySeparator = ' · ';

/// Κύρια γραμμή σύνοψης: «3 τμήματα · 12 υπάλληλοι · 2 κοινόχρηστα τηλέφωνα».
///
/// Το [subject] είναι το κυρίως αντικείμενο (τμήματα/υπάλληλοι/εξοπλισμοί) και
/// γράφεται **πάντα**. Τα [details] παραλείπονται όταν είναι μηδενικά, ώστε η
/// γραμμή να μη γεμίζει «0 τηλέφωνα · 0 εξοπλισμοί».
///
/// Όταν ο χρήστης αφαίρεσε στοιχεία από τη λίστα, το [initiallySelected] κάνει
/// το πρώτο σκέλος «Ν από τα Μ επιλεγμένα»: αλλιώς η σύνοψη διαφωνεί σιωπηλά
/// με το «Μ επιλεγμένα» της οθόνης από πίσω.
String buildBulkDeletionHeadline({
  required SummaryCount subject,
  int? initiallySelected,
  List<SummaryCount> details = const [],
}) {
  final removedSome =
      initiallySelected != null && initiallySelected > subject.count;
  final parts = <String>[
    if (removedSome)
      '${subject.count} από τα $initiallySelected επιλεγμένα'
    else
      subject.label,
    for (final detail in details)
      if (detail.count > 0) detail.label,
  ];
  return parts.join(kSummarySeparator);
}
