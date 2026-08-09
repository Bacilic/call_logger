/// Είδος οντότητας καταλόγου στην οποία εντοπίστηκε παρατυπία.
enum CatalogEntityKind { user, department, equipment }

/// Μία παρατυπία σε υπάρχουσα εγγραφή του καταλόγου.
///
/// Παράγεται από τη σάρωση των αποθηκευμένων δεδομένων με τους ενεργούς
/// κανόνες. Κουβαλά ό,τι χρειάζεται το UI για να ανοίξει τον σωστό διάλογο
/// επεξεργασίας, εστιασμένο στο πεδίο που φταίει.
class CatalogValidationFinding {
  const CatalogValidationFinding({
    required this.kind,
    required this.entityId,
    required this.entityLabel,
    required this.fieldLabel,
    required this.message,
    required this.focusedField,
  });

  final CatalogEntityKind kind;

  /// Ταυτότητα της εγγραφής — με αυτήν ξαναβρίσκεται για επεξεργασία.
  final int entityId;

  /// Πώς αναγνωρίζει ο χρήστης την εγγραφή («Ψαρρά Σοφία», «Γραμματεία ΤΕΠ»).
  final String entityLabel;

  /// Το πεδίο που φταίει, όπως γράφεται στη φόρμα («Τηλέφωνο», «Κωδικός»).
  final String fieldLabel;

  /// Η υπόδειξη του κανόνα που παραβιάζεται.
  final String message;

  /// Κλειδί εστίασης του διαλόγου επεξεργασίας (π.χ. `phone`, `lastName`).
  final String focusedField;
}
