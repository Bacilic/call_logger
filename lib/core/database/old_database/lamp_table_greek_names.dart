/// Εμφανιζόμενα ελληνικά ονόματα αντί αγγλικού ονόματος πίνακα (παλιά βάση Λάμπα).
const Map<String, String> kLampTableDisplayNamesGreek = {
  'equipment': 'Εξοπλισμός',
  'data_issues': 'Προβλήματα ETL (εισαγωγή Excel)',
  'offices': 'Γραφεία / τμήματα (offices)',
  'owners': 'Ιδιοκτήτες (owners)',
  'model': 'Μοντέλα (model)',
  'contracts': 'Συμβάσεις (contracts)',
  'meta': 'Μετα-δεδομένα (meta)',
  'etl_run': 'Εκτέλεση ETL (etl_run)',
  'import_log': 'Καταγραφή import (import_log)',
};

String lampTableDisplayGreek(String tableName) =>
    kLampTableDisplayNamesGreek[tableName] ?? tableName;

/// Σειρά πινάκων στο UI: γνωστοί τυπικοί πρώτα, οι λοιποί αλφαβητικά τελικά.
int lampTableSortOrderKey(String a, String b) {
  const preferred = <String>[
    'equipment',
    'data_issues',
    'offices',
    'owners',
    'model',
    'contracts',
  ];
  final ia = preferred.indexOf(a);
  final ib = preferred.indexOf(b);
  if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
  if (ia >= 0) return -1;
  if (ib >= 0) return 1;
  return a.compareTo(b);
}

List<String> lampOrderedTableNames(List<String> raw) {
  final c = List<String>.from(raw);
  c.sort(lampTableSortOrderKey);
  return c;
}
