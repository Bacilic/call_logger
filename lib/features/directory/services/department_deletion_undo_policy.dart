/// Αποτέλεσμα πολιτικής αναίρεσης μετά από διαγραφή τμήματος.
typedef DepartmentDeletionUndoDecision = ({
  bool canOfferUndo,
  String snackbarMessage,
});

/// Αποφασίζει αν προσφέρεται αναίρεση και ποιο μήνυμα εμφανίζεται στο snackbar.
DepartmentDeletionUndoDecision resolveDepartmentDeletionUndo({
  required int deletedDepartmentCount,
  required int movedEmployeeCount,
  required int movedOrDeletedAssetCount,
}) {
  final label = deletedDepartmentCount == 1 ? 'τμήμα' : 'τμήματα';
  final baseMessage =
      'Σημειώθηκαν ως διαγραμμένα $deletedDepartmentCount $label.';

  if (movedEmployeeCount == 0 && movedOrDeletedAssetCount == 0) {
    return (canOfferUndo: true, snackbarMessage: baseMessage);
  }

  return (
    canOfferUndo: false,
    snackbarMessage:
        'Το τμήμα διαγράφηκε, αλλά υπάλληλοι ή στοιχεία μετακινήθηκαν σε άλλα '
        'τμήματα· η ενέργεια δεν αναιρείται αυτόματα (η επαναφορά του τμήματος '
        'θα το έφερνε πίσω άδειο).',
  );
}
