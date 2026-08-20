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
    // «Υπάλληλοι» και όχι «Χρήστες»: ο πίνακας κρατά το προσωπικό του
    // νοσοκομείου. Οι «Χρήστες» είναι πλέον όσοι χειρίζονται την εφαρμογή
    // (`operators`) — δύο έννοιες δεν μοιράζονται την ίδια λέξη.
    'users' => 'Υπάλληλοι',
    'operators' => 'Χρήστες',
    'operator_settings' => 'Ρυθμίσεις χρηστών',
    'phones' => 'Τηλέφωνα',
    'departments' => 'Τμήματα',
    'equipment' => 'Εξοπλισμός',
    'categories' => 'Κατηγορίες',
    'user_phones' => 'Συσχέτιση υπαλλήλου–τηλεφώνου',
    'user_equipment' => 'Συσχέτιση υπαλλήλου–εξοπλισμού',
    'department_phones' => 'Συσχέτιση τμήματος–τηλεφώνου',
    'call_external_links' => 'Εξωτερικός σύνδεσμος κλήσης',
    'building_map_floors' => 'Όροφοι χάρτη κτιρίου',
    'audit_log' => 'Ιστορικό εφαρμογής',
    'app_settings' => 'Ρυθμίσεις εφαρμογής',
    'remote_tools' => 'Εργαλεία απομακρυσμένης',
    'remote_tool_args' => 'Ορίσματα εργαλείων',
    'full_dictionary' => 'Λεξικό',
    // Εδώ το «χρήστη» είναι σωστό: το προσωπικό λεξικό ορθογραφίας ανήκει σε
    // αυτόν που χειρίζεται την εφαρμογή, όχι σε υπάλληλο του καταλόγου.
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
    'user' => 'Υπάλληλος',
    'department' => 'Τμήμα',
    'equipment' => 'Εξοπλισμός',
    'category' => 'Κατηγορία',
    'task' => 'Εκκρεμότητα',
    'call' => 'Κλήση',
    'phone' => 'Τηλέφωνο',
    'bulk_users' => 'Μαζική ενημέρωση υπαλλήλων',
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
