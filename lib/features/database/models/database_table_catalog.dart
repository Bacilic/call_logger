/// Ο κατάλογος των πινάκων της βάσης όπως τον βλέπει ο χρήστης: ελληνικό
/// όνομα για κάθε πίνακα, και η σειρά τους όπως η πλευρική μπάρα.
///
/// Πίνακας που λείπει από τη σειρά εμφανίζεται μετά τους γνωστούς,
/// αλφαβητικά.
library;

import '../../../core/database/database_table_labels.dart';

/// Το ελληνικό όνομα έρχεται από το κοινό λεξιλόγιο της εφαρμογής, ώστε ο
/// ίδιος πίνακας να λέγεται παντού το ίδιο (Βάση Δεδομένων, Έλεγχος
/// Ακεραιότητας).
String databaseTableDisplayName(String tableName) =>
    databaseTableLabelEl(tableName);

/// Σειρά πινάκων όπως η πλευρική μπάρα της εφαρμογής: Κλήσεις → Εκκρεμότητες →
/// Κατάλογος → (Ιστορικό: ίδια δεδομένα με `calls`) → ρυθμίσεις/εποπτεία.
const List<String> _kMenuTableOrder = [
  // Κλήσεις
  'calls',
  'categories',
  'call_external_links',
  // Εκκρεμότητες
  'tasks',
  'task_notifications',
  // Κατάλογος
  'users',
  'departments',
  'equipment',
  'phones',
  'user_phones',
  'department_phones',
  'user_equipment',
  'building_map_floors',
  'building_map_floor_images',
  'building_map_plan_elements',
  'building_map_floor_state',
  'building_map_object_kinds',
  'building_map_objects',
  'building_map_placements',
  'building_map_ports',
  'building_map_cables',
  'building_map_cable_ends',
  // Βάση Δεδομένων / λοιπά
  'app_settings',
  'operators',
  'operator_settings',
  'operator_presence',
  'servers',
  'audit_log',
  'knowledge_base',
  'remote_tools',
  'remote_tool_args',
  'user_dictionary',
  'full_dictionary',
];

List<String> orderDatabaseTableNames(List<String> raw) {
  final orderMap = {
    for (var i = 0; i < _kMenuTableOrder.length; i++) _kMenuTableOrder[i]: i,
  };
  final copy = List<String>.from(raw);
  copy.sort((a, b) {
    final ia = orderMap[a];
    final ib = orderMap[b];
    if (ia != null && ib != null) return ia.compareTo(ib);
    if (ia != null) return -1;
    if (ib != null) return 1;
    return a.compareTo(b);
  });
  return copy;
}
