/// Είδος οντότητας καταλόγου στην οποία εντοπίστηκε παρατυπία.
enum CatalogEntityKind { user, department, equipment }

/// Είδος κανόνα που γέννησε το εύρημα — καθορίζει εικονίδιο/παρουσίαση.
enum CatalogFindingType {
  /// Ανά-πεδίο κανόνας: μία εγγραφή, ένα πεδίο.
  fieldHint,

  /// Τηλέφωνο που ταυτίζεται με καταχωρημένο κωδικό εξοπλισμού.
  phoneEquipmentCode,

  /// Ίδιο ή αντεστραμμένο ονοματεπώνυμο — πιθανό ίδιο πρόσωπο.
  nameConflict,

  /// Ίδιο τηλέφωνο σε υπαλλήλους διαφορετικών τμημάτων.
  crossDepartmentPhone,

  /// Εξοπλισμός χρεωμένος σε υπάλληλο άλλου τμήματος.
  equipmentOwnerDepartment,
}

/// Μία εμπλεκόμενη εγγραφή ενός ευρήματος.
///
/// Στα ευρήματα-διενέξεις κάθε κάρτα κουβαλά ΟΛΕΣ τις εμπλεκόμενες εγγραφές
/// ως επιλέξιμα chips — η απόφαση «ποια διορθώνω» θέλει όλες τις καρτέλες.
class CatalogFindingRecord {
  const CatalogFindingRecord({
    required this.kind,
    required this.entityId,
    required this.label,
    required this.focusedField,
    this.details = '',
    this.isNewest = false,
    this.createdAt,
    this.lastChangedAt,
  });

  final CatalogEntityKind kind;

  /// Ταυτότητα της εγγραφής — με αυτήν ξαναβρίσκεται για επεξεργασία.
  final int entityId;

  /// Πώς αναγνωρίζει ο χρήστης την εγγραφή («Ψαρρά Σοφία», «Γραμματεία ΤΕΠ»).
  final String label;

  /// Κλειδί εστίασης του διαλόγου επεξεργασίας (π.χ. `phone`, `lastName`).
  final String focusedField;

  /// Συνοπτικά στοιχεία για την απόφαση: «Πληροφορική · τηλ. 2854 · εξοπλ. 3604».
  final String details;

  /// Αληθές στη νεότερη εγγραφή μιας ομάδας ομοειδών — συνήθως το διπλότυπο.
  final bool isNewest;

  /// Χρονοσφραγίδες από το Ιστορικό Εφαρμογής — τις γεμίζει ο runner,
  /// όχι η καθαρή λογική της σάρωσης. `null` = χωρίς ίχνος στο Ιστορικό.
  final DateTime? createdAt;
  final DateTime? lastChangedAt;

  CatalogFindingRecord withStamps({
    DateTime? createdAt,
    DateTime? lastChangedAt,
  }) {
    return CatalogFindingRecord(
      kind: kind,
      entityId: entityId,
      label: label,
      focusedField: focusedField,
      details: details,
      isNewest: isNewest,
      createdAt: createdAt,
      lastChangedAt: lastChangedAt,
    );
  }
}

/// Μία παρατυπία στα δεδομένα του καταλόγου.
///
/// Παράγεται από τη σάρωση των αποθηκευμένων δεδομένων με τους ενεργούς
/// κανόνες. Στους ανά-πεδίο κανόνες αφορά ΜΙΑ εγγραφή· στις διασταυρώσεις
/// είναι διένεξη με όλες τις εμπλεκόμενες εγγραφές μαζί, σε μία κάρτα.
class CatalogValidationFinding {
  const CatalogValidationFinding({
    required this.type,
    required this.message,
    required this.records,
    this.fieldLabel = '',
  });

  final CatalogFindingType type;

  /// Η υπόδειξη του κανόνα που παραβιάζεται.
  final String message;

  /// Το πεδίο που φταίει στους ανά-πεδίο κανόνες («Τηλέφωνο», «Κωδικός»).
  /// Κενό στις διενέξεις — εκεί μιλούν τα chips.
  final String fieldLabel;

  /// Οι εμπλεκόμενες εγγραφές — μία στους ανά-πεδίο κανόνες, όλες μαζί
  /// στις διενέξεις.
  final List<CatalogFindingRecord> records;

  /// Αληθές όταν το εύρημα είναι διένεξη μεταξύ εγγραφών.
  bool get isConflict => records.length > 1;

  /// Η κύρια εγγραφή — στους ανά-πεδίο κανόνες η μοναδική.
  CatalogFindingRecord get primary => records.first;

  CatalogValidationFinding withRecords(List<CatalogFindingRecord> next) {
    return CatalogValidationFinding(
      type: type,
      message: message,
      fieldLabel: fieldLabel,
      records: next,
    );
  }
}
