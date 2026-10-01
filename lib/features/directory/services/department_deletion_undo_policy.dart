import '../../../core/utils/count_phrase.dart';

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
  final baseMessage = byCount(
    deletedDepartmentCount,
    one: 'Σημειώθηκε ως διαγραμμένο 1 τμήμα.',
    many: 'Σημειώθηκαν ως διαγραμμένα $deletedDepartmentCount τμήματα.',
  );

  if (movedEmployeeCount == 0 && movedOrDeletedAssetCount == 0) {
    return (canOfferUndo: true, snackbarMessage: baseMessage);
  }

  return (
    canOfferUndo: true,
    snackbarMessage: '$baseMessage Επαναφέρθηκαν και τα μετακινημένα στοιχεία.',
  );
}
