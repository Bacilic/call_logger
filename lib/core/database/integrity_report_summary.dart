/// Σύνοψη του ωμού κειμένου ελέγχου ακεραιότητας, για την οθόνη.
///
/// Το `PRAGMA quick_check` σε σοβαρά φθαρμένη βάση δεν απαντά με μία πρόταση:
/// επιστρέφει **μία γραμμή ανά χαλασμένη σελίδα** — εκατοντάδες «Tree 18 page
/// 2141 cell 3: …». Είναι τεκμήριο για αρχείο καταγραφής, όχι κείμενο για την
/// οθόνη εκκίνησης: ο χειριστής δεν μπορεί να κάνει τίποτα με τη λίστα, και η
/// οθόνη έσπαγε προσπαθώντας να τη χωρέσει.
///
/// Η σύνοψη ζει εδώ, χωριστά από τον έλεγχο, επειδή ο έλεγχος έχει δικό του
/// συμβόλαιο: το ωμό κείμενο περνά **αυτούσιο** ως το σημείο που θα το δείξει.
/// Η περικοπή είναι απόφαση της παρουσίασης, όχι της μέτρησης.
class IntegrityReportSummary {
  const IntegrityReportSummary({
    required this.findingCount,
    required this.forDisplay,
    required this.full,
  });

  /// Πόσες γραμμές ευρημάτων μέτρησε ο έλεγχος.
  final int findingCount;

  /// Ό,τι επιτρέπεται να μπει σε οθόνη — φραγμένου μήκους.
  final String forDisplay;

  /// Το πλήρες κείμενο, αυτούσιο. Προορίζεται για το αρχείο καταγραφής.
  final String full;

  /// Αληθές όταν η οθόνη βλέπει λιγότερα από όσα βρέθηκαν.
  bool get wasTrimmed => forDisplay != full;
}

/// Κόβει το ωμό κείμενο του ελέγχου σε κάτι που χωρά σε οθόνη.
///
/// Φράζει **και τις δύο** διαστάσεις: το πλήθος των γραμμών και το μήκος της
/// καθεμιάς. Μία μόνη γραμμή 4.000 χαρακτήρων ξεχειλίζει εξίσου με τετρακόσιες
/// κοντές.
IntegrityReportSummary summarizeIntegrityReport(
  String raw, {
  int sampleLines = 3,
  int maxLineLength = 160,
}) {
  final full = raw.trim();
  final lines = full
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  if (lines.isEmpty) {
    return const IntegrityReportSummary(
      findingCount: 0,
      forDisplay: '',
      full: '',
    );
  }

  final clipped = lines
      .map((line) => _clipLine(line, maxLineLength))
      .toList(growable: false);

  if (lines.length <= sampleLines) {
    return IntegrityReportSummary(
      findingCount: lines.length,
      forDisplay: clipped.join('\n'),
      full: full,
    );
  }

  final sample = clipped.take(sampleLines).join('\n');
  return IntegrityReportSummary(
    findingCount: lines.length,
    forDisplay:
        'Βρέθηκαν ${lines.length} προβλήματα στο περιεχόμενο της βάσης — '
        'δείγμα από τα πρώτα:\n'
        '$sample\n'
        'Ολόκληρη η λίστα καταγράφηκε στο ημερολόγιο σφαλμάτων.',
    full: full,
  );
}

String _clipLine(String line, int maxLength) =>
    line.length <= maxLength ? line : '${line.substring(0, maxLength)}…';
