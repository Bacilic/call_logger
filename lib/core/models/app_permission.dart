/// Ο κατάλογος των δικαιωμάτων που μπορεί να ρυθμίσει ο διαχειριστής.
///
/// **Κάθε δικαίωμα δηλώνει εδώ την προεπιλογή του.** Στην καρτέλα του χρήστη
/// αποθηκεύεται μόνο ό,τι ο διαχειριστής άλλαξε ρητά, οπότε η προσθήκη νέου
/// δικαιώματος δεν αγγίζει κανένα υπάρχον προφίλ: όσοι δεν το έχουν ρυθμίσει
/// παίρνουν αυτόματα την προεπιλογή που γράφεται εδώ.
///
/// Σχεδόν όλα επιτρέπονται από προεπιλογή — ο κατάλογος υπάρχει ως υποδομή.
/// Η γενική επιβολή, και η επιλογή του τι κλειδώνει και για ποιον, είναι
/// ξεχωριστή δουλειά με δική της οθόνη (Φάση 4). Η προεπιλογή γράφεται ρητά
/// σε κάθε εγγραφή ώστε η μελλοντική αλλαγή της να φαίνεται.
///
/// **Πρώτη εξαίρεση (Φάση 2, 20/08/2026): το πλήρες αντίγραφο ασφαλείας.**
/// Κλειδωμένη απόφαση: ένα επίσημο αντίγραφο της βάσης, μόνο ο διαχειριστής —
/// αλλιώς κάθε συνάδελφος θα έβγαζε δικά του αντίγραφα σε δικούς του φακέλους
/// και κανείς δεν θα ήξερε ποιο είναι το αληθινό.
enum AppPermission {
  manageEmployees(
    key: 'manage_employees',
    label: 'Καταχώρηση και επεξεργασία υπαλλήλων',
    allowedByDefault: true,
  ),
  manageDepartments(
    key: 'manage_departments',
    label: 'Προσθήκη και αλλαγή τμημάτων και ορόφων',
    allowedByDefault: true,
  ),
  manageEquipmentTypes(
    key: 'manage_equipment_types',
    label: 'Αλλαγή τύπων εξοπλισμού',
    allowedByDefault: true,
  ),
  manageSharedInfrastructure(
    key: 'manage_shared_infrastructure',
    label: 'Ρυθμίσεις κοινής υποδομής (Lansweeper, ΤΝ, φάκελος ενημερώσεων)',
    allowedByDefault: true,
  ),
  manageAuditRetention(
    key: 'manage_audit_retention',
    label: 'Πολιτική εκκαθάρισης Ιστορικού',
    allowedByDefault: true,
  ),
  bulkDelete(
    key: 'bulk_delete',
    label: 'Μαζικές διαγραφές',
    allowedByDefault: true,
  ),
  databaseMaintenance(
    key: 'database_maintenance',
    label: 'Συντήρηση και επαναφορά βάσης',
    allowedByDefault: true,
  ),
  /// `false` από τη Φάση 2: μόνο ο διαχειριστής (ή όποιος πάρει ρητό τικ στη
  /// Φάση 4). Χωρίς συνδεδεμένο χρήστη η πύλη απαντά «ναι» — ζώνη ασφαλείας
  /// από λάθη, όχι κλειδαριά.
  fullBackup(
    key: 'full_backup',
    label: 'Πλήρες αντίγραφο ασφαλείας',
    allowedByDefault: false,
  ),
  publishVersion(
    key: 'publish_version',
    label: 'Δημοσίευση έκδοσης',
    allowedByDefault: true,
  ),

  /// Χρειάζεται έμφαση: η Περιήγηση Βάσης **παρακάμπτει κάθε άλλο δικαίωμα**,
  /// γιατί δείχνει τους ωμούς πίνακες — άρα και ό,τι έχει κρυφτεί αλλού.
  browseDatabase(
    key: 'browse_database',
    label: 'Περιήγηση Βάσης',
    allowedByDefault: true,
  );

  const AppPermission({
    required this.key,
    required this.label,
    required this.allowedByDefault,
  });

  /// Το κλειδί που αποθηκεύεται. **Δεν αλλάζει ποτέ** — αποθηκευμένα προφίλ το
  /// αναφέρουν ονομαστικά, οπότε μια μετονομασία θα έσβηνε σιωπηλά ρυθμίσεις.
  final String key;

  /// Πώς διαβάζεται στην οθόνη διαχείρισης.
  final String label;

  final bool allowedByDefault;

  static AppPermission? byKey(String key) {
    final normalized = key.trim();
    for (final permission in AppPermission.values) {
      if (permission.key == normalized) return permission;
    }
    return null;
  }
}
