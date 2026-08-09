/// Πρόοδος στη σειρά χειροκίνητων βημάτων επίλυσης.
///
/// Δύο μετρήσεις, γιατί απαντούν σε διαφορετικά ερωτήματα:
/// - **Βήματα** ([stepNumber]/[totalSteps]) — πόσες φορές ακόμη θα χρειαστεί
///   να αποφασίσεις. Είναι λιγότερα από τις προτάσεις: οι όμοιες τιμές
///   συγχωνεύονται σε ένα βήμα και οι αυτόματες δεν ρωτούν καθόλου.
/// - **Προτάσεις** ([proposalsDone]/[totalProposals]) — πόσα από τα σφάλματα
///   που είδες στη λίστα έχουν καλυφθεί. Αυτόν τον αριθμό είδε ο χρήστης ως
///   «121» και τον αναζητά για να συνδέσει την πρόοδο με ό,τι ξεκίνησε.
library;

class LampManualReviewProgress {
  const LampManualReviewProgress({
    required this.stepNumber,
    required this.totalSteps,
    required this.proposalsDone,
    required this.totalProposals,
  });

  /// 1-based θέση του τρέχοντος χειροκίνητου βήματος.
  final int stepNumber;

  /// Συνολικά χειροκίνητα βήματα της σειράς.
  final int totalSteps;

  /// Προτάσεις που έχουν ήδη καλυφθεί (αυτόματες και χειροκίνητες).
  final int proposalsDone;

  final int totalProposals;

  /// Πόσα βήματα μένουν **μετά** το τρέχον.
  int get remainingSteps {
    final remaining = totalSteps - stepNumber;
    return remaining < 0 ? 0 : remaining;
  }

  /// Ποσοστό ολοκλήρωσης σε προτάσεις, 0–1 — οδηγεί τη μπάρα προόδου.
  ///
  /// Οι προτάσεις δίνουν ομαλότερη μπάρα από τα βήματα: ένα βήμα που καλύπτει
  /// 30 όμοιες εγγραφές είναι πολύ μεγαλύτερη πρόοδος από ένα που καλύπτει μία.
  double get fraction {
    if (totalProposals <= 0) return 0;
    final value = proposalsDone / totalProposals;
    if (value < 0) return 0;
    return value > 1 ? 1 : value;
  }

  /// «Βήμα 3 από 47» — ή σκέτο «Βήμα 3» αν το σύνολο δεν είναι γνωστό.
  String get stepLabel =>
      totalSteps > 0 ? 'Βήμα $stepNumber από $totalSteps' : 'Βήμα $stepNumber';

  /// «απομένουν 44» — κενό στο τελευταίο βήμα, όπου δεν απομένει τίποτα.
  String get remainingLabel {
    final remaining = remainingSteps;
    if (remaining <= 0) return 'τελευταίο βήμα';
    return remaining == 1 ? 'απομένει 1' : 'απομένουν $remaining';
  }

  /// «12 από 121 προτάσεις» — ο αριθμός που ο χρήστης είδε ως σφάλματα.
  String get proposalsLabel =>
      '$proposalsDone από $totalProposals προτάσεις';
}
