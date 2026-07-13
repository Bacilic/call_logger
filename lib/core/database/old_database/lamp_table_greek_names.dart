/// Εμφανιζόμενα ελληνικά ονόματα αντί αγγλικού ονόματος πίνακα (παλιά βάση Λάμπα).
const Map<String, String> kLampTableDisplayNamesGreek = {
  'equipment': 'Εξοπλισμός',
  'data_issues': 'Προβλήματα ETL (εισαγωγή Excel)',
  'offices': 'Γραφεία / τμήματα (offices)',
  'owners': 'Ιδιοκτήτες (owners)',
  'model': 'Μοντέλα (model)',
  'contracts': 'Συμβάσεις (contracts)',
  'search_index': 'Ευρετηρίαση (search_index)',
  'meta': 'Μετα-δεδομένα (meta)',
  'etl_run': 'Εκτέλεση ETL (etl_run)',
  'import_log': 'Καταγραφή import (import_log)',
};

String lampTableDisplayGreek(String tableName) =>
    kLampTableDisplayNamesGreek[tableName] ?? tableName;

/// Σειρά πινάκων στο UI: πίνακες δεδομένων πρώτα, άγνωστοι αλφαβητικά, τεχνικοί τελευταίοι.
int lampTableSortOrderKey(String a, String b) {
  const dataTables = <String>[
    'equipment',
    'offices',
    'owners',
    'model',
    'contracts',
  ];
  const technicalTables = <String>[
    'data_issues',
    'search_index',
  ];

  final isTechA = technicalTables.contains(a);
  final isTechB = technicalTables.contains(b);
  if (isTechA && isTechB) {
    return technicalTables.indexOf(a).compareTo(technicalTables.indexOf(b));
  }
  if (isTechA) return 1;
  if (isTechB) return -1;

  final ia = dataTables.indexOf(a);
  final ib = dataTables.indexOf(b);
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
