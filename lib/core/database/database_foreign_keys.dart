// Οι δηλωμένοι κανόνες σχέσεων (foreign keys) και η αναβάθμιση που τους φέρνει.
//
// **Γιατί δεν μπαίνουν παντού.** Οι στήλες-δείκτες του σχήματος δεν είναι όλες
// το ίδιο πράγμα:
//
// - **Συσχετίσεις** (`user_phones`, `department_phones`, `user_equipment`) και
//   **παιδιά** (`call_external_links`, `remote_tool_args`) δεν έχουν νόημα χωρίς
//   τον γονιό τους → `ON DELETE CASCADE`.
// - **Ζωντανές αναφορές** (`users.department_id`, `tasks.call_id`, …) επιβιώνουν
//   ορφανές, απλώς χάνουν τον δεσμό → `ON DELETE SET NULL`.
// - **Ιστορικά στιγμιότυπα** (`calls.caller_id`, `calls.equipment_id`,
//   `tasks.caller_id`, …) μένουν **σκόπιμα χωρίς κανόνα**. Κάθε μία έχει δίπλα
//   της αδελφή στήλη κειμένου (`caller_text`, `equipment_text`) ακριβώς επειδή
//   η κλήση κρατά τι ίσχυε τη μέρα που έγινε. Ένα `ON DELETE SET NULL` εκεί θα
//   πήγαινε πίσω και θα άλλαζε ιστορικά δεδομένα — και θα έσβηνε τη δυνατότητα
//   «δείξε μου όλες τις κλήσεις αυτού του υπαλλήλου». Αυτές τις φυλάει ο
//   Έλεγχος Ακεραιότητας, που τις αναφέρει χωρίς να τις πειράζει.

import 'package:sqflite_common/sqlite_api.dart';

/// Πίνακας που ξαναχτίζεται στην v38 για να αποκτήσει τους κανόνες του.
class ForeignKeyTableDefinition {
  const ForeignKeyTableDefinition({
    required this.name,
    required this.createSql,
    this.indexes = const <String>[],
  });

  final String name;
  final String createSql;
  final List<String> indexes;
}

const String kCreateCallExternalLinksTable = '''
CREATE TABLE IF NOT EXISTS call_external_links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  call_id INTEGER NOT NULL,
  external_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  created_at TEXT NOT NULL,
  metadata TEXT,
  FOREIGN KEY (call_id) REFERENCES calls(id) ON DELETE CASCADE
)
''';

const String kCreateUsersTable = '''
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  last_name TEXT NOT NULL,
  first_name TEXT NOT NULL,
  department_id INTEGER,
  location TEXT,
  notes TEXT,
  lansweeper_username TEXT,
  is_deleted INTEGER DEFAULT 0,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
)
''';

const String kCreatePhonesTable = '''
CREATE TABLE phones (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  number TEXT UNIQUE NOT NULL,
  department_id INTEGER,
  is_deleted INTEGER DEFAULT 0,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
)
''';

const String kCreateDepartmentPhonesTable = '''
CREATE TABLE department_phones (
  department_id INTEGER NOT NULL,
  phone_id INTEGER NOT NULL,
  PRIMARY KEY (department_id, phone_id),
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE CASCADE,
  FOREIGN KEY (phone_id) REFERENCES phones(id) ON DELETE CASCADE
)
''';

const String kCreateUserPhonesTable = '''
CREATE TABLE user_phones (
  user_id INTEGER NOT NULL,
  phone_id INTEGER NOT NULL,
  PRIMARY KEY (user_id, phone_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (phone_id) REFERENCES phones(id) ON DELETE CASCADE
)
''';

const String kCreateEquipmentTable = '''
CREATE TABLE equipment (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code_equipment TEXT,
  type TEXT,
  notes TEXT,
  remote_params TEXT,
  default_remote_tool TEXT,
  department_id INTEGER,
  location TEXT,
  lansweeper_asset_name TEXT,
  is_deleted INTEGER DEFAULT 0,
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL
)
''';

const String kCreateUserEquipmentTable = '''
CREATE TABLE user_equipment (
  user_id INTEGER NOT NULL,
  equipment_id INTEGER NOT NULL,
  PRIMARY KEY (user_id, equipment_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (equipment_id) REFERENCES equipment(id) ON DELETE CASCADE
)
''';

const String kCreateRemoteToolArgsTable = '''
CREATE TABLE IF NOT EXISTS remote_tool_args (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  remote_tool_id INTEGER,
  tool_name TEXT,
  arg_flag TEXT,
  description TEXT,
  is_active INTEGER DEFAULT 0,
  FOREIGN KEY (remote_tool_id) REFERENCES remote_tools(id) ON DELETE CASCADE
)
''';

const String kCreateDepartmentsTable = '''
CREATE TABLE departments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  name_key TEXT UNIQUE NOT NULL,
  building TEXT,
  color TEXT DEFAULT '#1976D2',
  notes TEXT,
  map_floor TEXT,
  map_x REAL DEFAULT 0.0,
  map_y REAL DEFAULT 0.0,
  map_width REAL DEFAULT 0.0,
  map_height REAL DEFAULT 0.0,
  map_rotation REAL DEFAULT 0.0,
  map_label_offset_x REAL,
  map_label_offset_y REAL,
  map_anchor_offset_x REAL,
  map_anchor_offset_y REAL,
  map_custom_name TEXT,
  map_label_font_scale REAL,
  map_label_width REAL DEFAULT 150.0,
  map_label_height REAL DEFAULT 50.0,
  group_name TEXT,
  floor_id INTEGER,
  lansweeper_usernames TEXT,
  is_deleted INTEGER DEFAULT 0,
  FOREIGN KEY (floor_id) REFERENCES building_map_floors(id) ON DELETE SET NULL
)
''';

const String kCreateTasksTable = '''
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT,
  description TEXT,
  due_date TEXT,
  snooze_history_json TEXT,
  status TEXT,
  call_id INTEGER,
  priority INTEGER,
  solution_notes TEXT,
  snooze_until TEXT,
  caller_id INTEGER,
  equipment_id INTEGER,
  department_id INTEGER,
  phone_id INTEGER,
  phone_text TEXT,
  user_text TEXT,
  equipment_text TEXT,
  department_text TEXT,
  created_at TEXT,
  updated_at TEXT,
  completed_at TEXT,
  origin TEXT DEFAULT 'legacy',
  search_index TEXT,
  is_deleted INTEGER DEFAULT 0,
  FOREIGN KEY (call_id) REFERENCES calls(id) ON DELETE SET NULL
)
''';

/// Οι πίνακες που ξαναχτίζονται, με τη σειρά που τους αγγίζει η αναβάθμιση.
///
/// Το SQL γράφεται **μία** φορά και το διαβάζουν και η δημιουργία νέας βάσης και
/// η αναβάθμιση παλιάς: αλλιώς οι δύο δρόμοι θα απέκλιναν σιωπηλά, και μια
/// αναβαθμισμένη βάση δεν θα ήταν ίδια με μια καινούργια.
const List<ForeignKeyTableDefinition> kForeignKeyRebuiltTables = [
  ForeignKeyTableDefinition(
    name: 'call_external_links',
    createSql: kCreateCallExternalLinksTable,
    indexes: [
      'CREATE INDEX IF NOT EXISTS idx_call_external_links_call_provider '
          'ON call_external_links(call_id, provider)',
      'CREATE INDEX IF NOT EXISTS idx_call_external_links_created_at '
          'ON call_external_links(created_at)',
    ],
  ),
  ForeignKeyTableDefinition(name: 'users', createSql: kCreateUsersTable),
  ForeignKeyTableDefinition(name: 'phones', createSql: kCreatePhonesTable),
  ForeignKeyTableDefinition(
    name: 'department_phones',
    createSql: kCreateDepartmentPhonesTable,
  ),
  ForeignKeyTableDefinition(
    name: 'user_phones',
    createSql: kCreateUserPhonesTable,
  ),
  ForeignKeyTableDefinition(name: 'equipment', createSql: kCreateEquipmentTable),
  ForeignKeyTableDefinition(
    name: 'user_equipment',
    createSql: kCreateUserEquipmentTable,
  ),
  ForeignKeyTableDefinition(
    name: 'remote_tool_args',
    createSql: kCreateRemoteToolArgsTable,
  ),
  ForeignKeyTableDefinition(
    name: 'departments',
    createSql: kCreateDepartmentsTable,
  ),
  ForeignKeyTableDefinition(name: 'tasks', createSql: kCreateTasksTable),
];

/// Μία σπασμένη σχέση και ο τρόπος που την τακτοποιεί η αναβάθμιση.
class BrokenReferenceRepair {
  const BrokenReferenceRepair({
    required this.label,
    required this.countSql,
    required this.repairSql,
  });

  /// Πώς περιγράφεται στο Ιστορικό Εφαρμογής.
  final String label;
  final String countSql;
  final String repairSql;
}

/// Οι σπασμένες σχέσεις που πρέπει να φύγουν **πριν** μπουν οι κανόνες.
///
/// Χωρίς αυτό το βήμα η αναβάθμιση θα περνούσε καθαρά — η SQLite δεν ελέγχει
/// αναδρομικά όταν ανάβει ο διακόπτης — και κάθε παλιά σπασμένη γραμμή θα
/// έσκαγε αργότερα, σε τυχαία στιγμή, μπροστά στον χρήστη.
const List<BrokenReferenceRepair> kBrokenReferenceRepairs = [
  BrokenReferenceRepair(
    label: 'συσχετίσεις τμήματος-τηλεφώνου με ανύπαρκτο τμήμα ή τηλέφωνο',
    countSql:
        'SELECT COUNT(*) AS c FROM department_phones '
        'WHERE department_id NOT IN (SELECT id FROM departments) '
        'OR phone_id NOT IN (SELECT id FROM phones)',
    repairSql:
        'DELETE FROM department_phones '
        'WHERE department_id NOT IN (SELECT id FROM departments) '
        'OR phone_id NOT IN (SELECT id FROM phones)',
  ),
  BrokenReferenceRepair(
    label: 'συσχετίσεις χρήστη-τηλεφώνου με ανύπαρκτο χρήστη ή τηλέφωνο',
    countSql:
        'SELECT COUNT(*) AS c FROM user_phones '
        'WHERE user_id NOT IN (SELECT id FROM users) '
        'OR phone_id NOT IN (SELECT id FROM phones)',
    repairSql:
        'DELETE FROM user_phones '
        'WHERE user_id NOT IN (SELECT id FROM users) '
        'OR phone_id NOT IN (SELECT id FROM phones)',
  ),
  BrokenReferenceRepair(
    label: 'συσχετίσεις χρήστη-εξοπλισμού με ανύπαρκτο χρήστη ή εξοπλισμό',
    countSql:
        'SELECT COUNT(*) AS c FROM user_equipment '
        'WHERE user_id NOT IN (SELECT id FROM users) '
        'OR equipment_id NOT IN (SELECT id FROM equipment)',
    repairSql:
        'DELETE FROM user_equipment '
        'WHERE user_id NOT IN (SELECT id FROM users) '
        'OR equipment_id NOT IN (SELECT id FROM equipment)',
  ),
  BrokenReferenceRepair(
    label: 'εγγραφές ιστορικού Lansweeper με ανύπαρκτη κλήση',
    countSql:
        'SELECT COUNT(*) AS c FROM call_external_links '
        'WHERE call_id NOT IN (SELECT id FROM calls)',
    repairSql:
        'DELETE FROM call_external_links '
        'WHERE call_id NOT IN (SELECT id FROM calls)',
  ),
  BrokenReferenceRepair(
    label: 'ορίσματα εργαλείων με ανύπαρκτο εργαλείο',
    countSql:
        'SELECT COUNT(*) AS c FROM remote_tool_args '
        'WHERE remote_tool_id IS NOT NULL '
        'AND remote_tool_id NOT IN (SELECT id FROM remote_tools)',
    repairSql:
        'DELETE FROM remote_tool_args '
        'WHERE remote_tool_id IS NOT NULL '
        'AND remote_tool_id NOT IN (SELECT id FROM remote_tools)',
  ),
  BrokenReferenceRepair(
    label: 'χρήστες σε ανύπαρκτο τμήμα (αποσυνδέθηκαν)',
    countSql:
        'SELECT COUNT(*) AS c FROM users '
        'WHERE department_id IS NOT NULL '
        'AND department_id NOT IN (SELECT id FROM departments)',
    repairSql:
        'UPDATE users SET department_id = NULL '
        'WHERE department_id IS NOT NULL '
        'AND department_id NOT IN (SELECT id FROM departments)',
  ),
  BrokenReferenceRepair(
    label: 'τηλέφωνα σε ανύπαρκτο τμήμα (αποσυνδέθηκαν)',
    countSql:
        'SELECT COUNT(*) AS c FROM phones '
        'WHERE department_id IS NOT NULL '
        'AND department_id NOT IN (SELECT id FROM departments)',
    repairSql:
        'UPDATE phones SET department_id = NULL '
        'WHERE department_id IS NOT NULL '
        'AND department_id NOT IN (SELECT id FROM departments)',
  ),
  BrokenReferenceRepair(
    label: 'εξοπλισμός σε ανύπαρκτο τμήμα (αποσυνδέθηκε)',
    countSql:
        'SELECT COUNT(*) AS c FROM equipment '
        'WHERE department_id IS NOT NULL '
        'AND department_id NOT IN (SELECT id FROM departments)',
    repairSql:
        'UPDATE equipment SET department_id = NULL '
        'WHERE department_id IS NOT NULL '
        'AND department_id NOT IN (SELECT id FROM departments)',
  ),
  BrokenReferenceRepair(
    label: 'τμήματα σε ανύπαρκτο όροφο χάρτη (αποσυνδέθηκαν)',
    countSql:
        'SELECT COUNT(*) AS c FROM departments '
        'WHERE floor_id IS NOT NULL '
        'AND floor_id NOT IN (SELECT id FROM building_map_floors)',
    repairSql:
        'UPDATE departments SET floor_id = NULL '
        'WHERE floor_id IS NOT NULL '
        'AND floor_id NOT IN (SELECT id FROM building_map_floors)',
  ),
  BrokenReferenceRepair(
    label: 'εκκρεμότητες σε ανύπαρκτη κλήση (αποσυνδέθηκαν)',
    countSql:
        'SELECT COUNT(*) AS c FROM tasks '
        'WHERE call_id IS NOT NULL '
        'AND call_id NOT IN (SELECT id FROM calls)',
    repairSql:
        'UPDATE tasks SET call_id = NULL '
        'WHERE call_id IS NOT NULL '
        'AND call_id NOT IN (SELECT id FROM calls)',
  ),
];

/// Καθαρίζει τις σπασμένες σχέσεις και επιστρέφει τι διορθώθηκε.
///
/// Το αποτέλεσμα είναι «ετικέτα → πλήθος», μόνο για όσα βρέθηκαν. Κενός χάρτης
/// σημαίνει βάση που ήταν ήδη συνεπής.
Future<Map<String, int>> repairBrokenReferences(DatabaseExecutor db) async {
  final repaired = <String, int>{};
  for (final repair in kBrokenReferenceRepairs) {
    final count = await _scalarCount(db, repair.countSql);
    if (count <= 0) continue;
    await db.execute(repair.repairSql);
    repaired[repair.label] = count;
  }
  return repaired;
}

/// Ενεργοποιεί τους κανόνες για **αυτή** τη σύνδεση.
///
/// Είναι ρύθμιση της σύνδεσης, όχι ιδιότητα του αρχείου: κάθε διαδρομή που
/// ανοίγει τη βάση οφείλει να την περάσει, αλλιώς οι κανόνες σιωπούν εκεί.
Future<void> enableForeignKeys(DatabaseExecutor db) async {
  await db.execute('PRAGMA foreign_keys = ON');
}

/// `true` όταν οι κανόνες είναι ενεργοί στη συγκεκριμένη σύνδεση.
Future<bool> areForeignKeysEnabled(DatabaseExecutor db) async {
  final rows = await db.rawQuery('PRAGMA foreign_keys');
  if (rows.isEmpty) return false;
  final value = rows.first.values.firstOrNull;
  if (value is int) return value == 1;
  if (value is bool) return value;
  return value?.toString() == '1';
}

/// Οι γραμμές που παραβιάζουν κανόνα — κενή λίστα σε υγιή βάση.
Future<List<Map<String, Object?>>> foreignKeyViolations(
  DatabaseExecutor db,
) async {
  return db.rawQuery('PRAGMA foreign_key_check');
}

/// v38: καθαρίζει τις σπασμένες σχέσεις και ξαναχτίζει τους πίνακες με κανόνες.
///
/// Επιστρέφει τι διορθώθηκε στην πορεία, ώστε ο καλών να το καταγράψει.
///
/// Η σειρά είναι δεσμευτική: **πρώτα** το καθάρισμα, μετά το ξαναχτίσιμο. Το
/// ξαναχτίσιμο τρέχει με τους κανόνες σβηστούς — αλλιώς κάθε `DROP TABLE` ενός
/// γονιού θα παρέσυρε τα παιδιά του — οπότε δεν θα έπιανε τίποτα μόνο του.
Future<Map<String, int>> migrateDatabaseToV38(Database db) async {
  await db.execute('PRAGMA foreign_keys = OFF');
  // Χωρίς αυτό, το `RENAME TO` ξαναγράφει τις αναφορές **άλλων** πινάκων ώστε
  // να δείχνουν στο προσωρινό όνομα: μετονομάζεις τον `departments`, και ο
  // `users` αρχίζει σιωπηλά να δείχνει στον `departments_pre_v38` — που σε λίγο
  // σβήνεται. Το αποτέλεσμα είναι βάση με κανόνες που δείχνουν στο πουθενά.
  await db.execute('PRAGMA legacy_alter_table = ON');
  try {
    final repaired = await repairBrokenReferences(db);
    for (final table in kForeignKeyRebuiltTables) {
      await _rebuildTableWithConstraints(db, table);
    }
    return repaired;
  } finally {
    await db.execute('PRAGMA legacy_alter_table = OFF');
    await enableForeignKeys(db);
  }
}

/// Ξαναχτίζει έναν πίνακα με το νέο του SQL, κρατώντας τα δεδομένα του.
///
/// Αντιγράφονται μόνο οι στήλες που υπάρχουν **και** στους δύο ορισμούς: έτσι
/// μια βάση που κουβαλά παλιά στήλη δεν σκοντάφτει, και μια νέα στήλη παίρνει
/// την προεπιλογή της αντί για σφάλμα.
Future<void> _rebuildTableWithConstraints(
  Database db,
  ForeignKeyTableDefinition table,
) async {
  final existing = await _columnNames(db, table.name);
  if (existing.isEmpty) return;

  final legacyName = '${table.name}_pre_v38';
  await db.execute('DROP TABLE IF EXISTS $legacyName');
  await db.execute('ALTER TABLE ${table.name} RENAME TO $legacyName');
  await db.execute(table.createSql);

  final target = await _columnNames(db, table.name);
  final shared = target.where(existing.contains).toList(growable: false);
  if (shared.isNotEmpty) {
    final columns = shared.join(', ');
    await db.execute(
      'INSERT INTO ${table.name} ($columns) SELECT $columns FROM $legacyName',
    );
  }

  await db.execute('DROP TABLE $legacyName');
  for (final index in table.indexes) {
    await db.execute(index);
  }
}

Future<List<String>> _columnNames(Database db, String table) async {
  try {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return [
      for (final row in rows)
        if (row['name'] case final String name) name,
    ];
  } catch (_) {
    // Ο πίνακας μπορεί να λείπει σε ελλιπές αρχείο· η αναβάθμιση τον προσπερνά
    // και τον φτιάχνει η κανονική δημιουργία σχήματος.
    return const <String>[];
  }
}

Future<int> _scalarCount(DatabaseExecutor db, String sql) async {
  final rows = await db.rawQuery(sql);
  if (rows.isEmpty) return 0;
  final value = rows.first['c'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
