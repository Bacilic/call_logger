/// Αποτέλεσμα πολιτικής αναίρεσης μετά από διαγραφή τμήματος.
typedef DepartmentDeletionUndoDecision = ({
  bool canOfferUndo,
  String snackbarMessage,
});

/// Αποφασίζει το μήνυμα snackbar· η αναίρεση προσφέρεται πάντα (πλήρης φάκελος).
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
    canOfferUndo: true,
    snackbarMessage: '$baseMessage Επαναφέρθηκαν και τα μετακινημένα στοιχεία.',
  );
}
