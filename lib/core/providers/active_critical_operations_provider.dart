import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Κρίσιμες ασύγχρονες ενέργειες που δεν πρέπει να διακοπούν με αλλαγή βάσης.
enum CriticalOperation {
  lansweeperTicketSubmit,

  /// Εναλλαγή αρχείου βάσης σε εξέλιξη (αλλαγή διαδρομής, δημιουργία, επαναφορά).
  ///
  /// Δηλώνεται από το [runGuardedDatabaseSwitch] και ΔΕΝ μπλοκάρει άλλη εναλλαγή —
  /// υπάρχει ώστε ο περιοδικός `_tick` του αντιγράφου ασφαλείας να μη φωτογραφίσει
  /// βάση που αλλάζει εκείνη τη στιγμή (η αντίστροφη φορά του ελέγχου
  /// `isBackupJobRunning` που κάνει ο φρουρός). Με μετρητή αναφορών αντέχει και
  /// φωλιασμένες ροές εναλλαγής: η δήλωση φεύγει μόνο όταν κλείσει ο τελευταίος κάτοχος.
  databaseSwitch,
}

/// Μητρώο ενεργών κρίσιμων ενεργειών (μη-autoDispose).
///
/// Η δήλωση είναι μετρημένη: κάθε [begin] απαιτεί ακριβώς ένα [end], και η ενέργεια
/// θεωρείται ενεργή όσο υπάρχει έστω ένας κάτοχος. Το δημόσιο [state] παραμένει
/// [Set] ώστε οι καταναλωτές να ρωτούν με `contains` χωρίς να γνωρίζουν τον μετρητή.
///
/// Το σήμα πρέπει να επιζεί όταν το widget που ξεκίνησε την ενέργεια καταστραφεί
/// (π.χ. κλείσιμο διαλόγου ιστορικού κατά την αποστολή Lansweeper).
class ActiveCriticalOperationsNotifier
    extends Notifier<Set<CriticalOperation>> {
  final Map<CriticalOperation, int> _refCounts = <CriticalOperation, int>{};

  @override
  Set<CriticalOperation> build() {
    _refCounts.clear();
    return const <CriticalOperation>{};
  }

  void begin(CriticalOperation op) {
    final next = (_refCounts[op] ?? 0) + 1;
    _refCounts[op] = next;
    if (next == 1) {
      state = {...state, op};
    }
  }

  void end(CriticalOperation op) {
    final current = _refCounts[op];
    if (current == null || current <= 0) {
      assert(
        false,
        'Αταίριαστο end($op) χωρίς αντίστοιχο begin — ανισορροπία δηλώσεων.',
      );
      return;
    }
    final next = current - 1;
    if (next == 0) {
      _refCounts.remove(op);
      state = {...state}..remove(op);
    } else {
      _refCounts[op] = next;
    }
  }
}

final activeCriticalOperationsProvider =
    NotifierProvider<ActiveCriticalOperationsNotifier, Set<CriticalOperation>>(
      ActiveCriticalOperationsNotifier.new,
    );
