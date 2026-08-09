/// Ελληνική απόδοση ονόματος πίνακα για ό,τι διαβάζει ο χρήστης.
///
/// Τα ονόματα των πινάκων μένουν αγγλικά μέσα στη βάση· εδώ μεταφράζονται μόνο
/// για εμφάνιση. Κάθε κείμενο του Ελέγχου Ακεραιότητας που αναφέρει πίνακα
/// περνά από εδώ, ώστε το ίδιο πράγμα να λέγεται παντού με το ίδιο όνομα.
///
/// Άγνωστος πίνακας επιστρέφεται ως έχει — προτιμότερο από το να εξαφανιστεί.
String databaseTableLabelEl(String? tableName) {
  final name = tableName?.trim() ?? '';
  if (name.isEmpty) return '—';
  return switch (name) {
    'calls' => 'Κλήσεις',
    'tasks' => 'Εκκρεμότητες',
    'users' => 'Χρήστες',
    'phones' => 'Τηλέφωνα',
    'departments' => 'Τμήματα',
    'equipment' => 'Εξοπλισμός',
    'categories' => 'Κατηγορίες',
    'user_phones' => 'Συσχέτιση χρήστη–τηλεφώνου',
    'user_equipment' => 'Συσχέτιση χρήστη–εξοπλισμού',
    'department_phones' => 'Συσχέτιση τμήματος–τηλεφώνου',
    'call_external_links' => 'Εξωτερικός σύνδεσμος κλήσης',
    'building_map_floors' => 'Όροφοι χάρτη κτιρίου',
    'audit_log' => 'Ιστορικό εφαρμογής',
    'app_settings' => 'Ρυθμίσεις εφαρμογής',
    'remote_tools' => 'Εργαλεία απομακρυσμένης',
    'remote_tool_args' => 'Ορίσματα εργαλείων',
    'full_dictionary' => 'Λεξικό',
    'user_dictionary' => 'Λεξικό χρήστη',
    'knowledge_base' => 'Βάση Γνώσης',
    _ => name,
  };
}

/// Ελληνική απόδοση του `entity_type` μιας εγγραφής ιστορικού.
///
/// Διαφορετικό λεξιλόγιο από το [databaseTableLabelEl]: εκεί μιλάμε για
/// πίνακες (πληθυντικός), εδώ για μία οντότητα (ενικός).
String databaseEntityTypeLabelEl(String? entityType) {
  final type = entityType?.trim() ?? '';
  if (type.isEmpty) return '—';
  return switch (type) {
    'user' => 'Χρήστης',
    'department' => 'Τμήμα',
    'equipment' => 'Εξοπλισμός',
    'category' => 'Κατηγορία',
    'task' => 'Εκκρεμότητα',
    'call' => 'Κλήση',
    'phone' => 'Τηλέφωνο',
    'bulk_users' => 'Μαζική ενημέρωση χρηστών',
    'bulk_departments' => 'Μαζική ενημέρωση τμημάτων',
    'bulk_equipment' => 'Μαζική ενημέρωση εξοπλισμού',
    'import_data' => 'Δεδομένα εισαγωγής',
    'maintenance' => 'Συντήρηση βάσης',
    'backup' => 'Αντίγραφο ασφαλείας',
    _ => type,
  };
}

/// «Τμήματα (`departments`)» — ελληνικό όνομα με το τεχνικό δίπλα.
///
/// Για τα ευρήματα που έρχονται ωμά από τη SQLite (`PRAGMA foreign_key_check`):
/// ο χρήστης διαβάζει ελληνικά, αλλά το όνομα του πίνακα μένει ορατό ώστε το
/// εύρημα να παραμένει διαγνώσιμο.
String databaseTableLabelWithTechnicalEl(String? tableName) {
  final name = tableName?.trim() ?? '';
  if (name.isEmpty) return '—';
  final label = databaseTableLabelEl(name);
  if (label == name) return name;
  return '$label ($name)';
}
