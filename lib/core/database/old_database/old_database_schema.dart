import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const List<String> oldDatabaseCreateStatements = <String>[
  '''
  CREATE TABLE offices (
    office INTEGER PRIMARY KEY,
    office_name TEXT,
    organization INTEGER,
    organization_name TEXT,
    department INTEGER,
    department_name TEXT,
    responsible INTEGER,
    responsible_original_text TEXT,
    e_mail TEXT,
    phones TEXT,
    building TEXT,
    level INTEGER
  )
  ''',
  '''
  CREATE TABLE owners (
    owner INTEGER PRIMARY KEY,
    last_name TEXT,
    first_name TEXT,
    office INTEGER,
    office_original_text TEXT,
    e_mail TEXT,
    phones TEXT,
    FOREIGN KEY (office) REFERENCES offices(office)
  )
  ''',
  '''
  CREATE TABLE model (
    model INTEGER PRIMARY KEY,
    model_name TEXT,
    category_code INTEGER,
    category_code_original_text TEXT,
    category_name TEXT,
    subcategory_code INTEGER,
    subcategory_code_original_text TEXT,
    subcategory_name TEXT,
    manufacturer INTEGER,
    manufacturer_original_text TEXT,
    manufacturer_name TEXT,
    manufacturer_code TEXT,
    attributes TEXT,
    consumables TEXT,
    network_connectivity INTEGER
  )
  ''',
  '''
  CREATE TABLE contracts (
    contract INTEGER PRIMARY KEY,
    contract_name TEXT,
    category INTEGER,
    category_original_text TEXT,
    category_name TEXT,
    supplier INTEGER,
    supplier_original_text TEXT,
    supplier_name TEXT,
    start_date TEXT,
    end_date TEXT,
    declaration TEXT,
    award TEXT,
    cost TEXT,
    committee TEXT,
    comments TEXT
  )
  ''',
  '''
  CREATE TABLE equipment (
    code INTEGER PRIMARY KEY,
    description TEXT,
    model INTEGER,
    model_original_text TEXT,
    serial_no TEXT,
    asset_no TEXT,
    state INTEGER,
    state_original_text TEXT,
    state_name TEXT,
    set_master INTEGER,
    set_master_original_text TEXT,
    contract INTEGER,
    contract_original_text TEXT,
    maintenance_contract TEXT,
    receiving_date TEXT,
    end_of_guarantee_date TEXT,
    cost TEXT,
    owner INTEGER,
    owner_original_text TEXT,
    office INTEGER,
    office_original_text TEXT,
    attributes TEXT,
    comments TEXT,
    FOREIGN KEY (model) REFERENCES model(model),
    FOREIGN KEY (contract) REFERENCES contracts(contract),
    FOREIGN KEY (owner) REFERENCES owners(owner),
    FOREIGN KEY (office) REFERENCES offices(office),
    FOREIGN KEY (set_master) REFERENCES equipment(code)
  )
  ''',
  '''
  CREATE TABLE data_issues (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sheet TEXT,
    row_number INTEGER,
    column_name TEXT,
    raw_value TEXT,
    issue_type TEXT NOT NULL,
    message TEXT,
    created_at TEXT NOT NULL
  )
  ''',
];

const List<String> oldDatabaseIndexStatements = <String>[
  'CREATE INDEX IF NOT EXISTS idx_equipment_asset_no ON equipment(asset_no)',
  'CREATE INDEX IF NOT EXISTS idx_equipment_serial_no ON equipment(serial_no)',
  'CREATE INDEX IF NOT EXISTS idx_equipment_owner_original_text ON equipment(owner_original_text)',
  'CREATE INDEX IF NOT EXISTS idx_equipment_office_original_text ON equipment(office_original_text)',
  'CREATE INDEX IF NOT EXISTS idx_owners_phones ON owners(phones)',
  'CREATE INDEX IF NOT EXISTS idx_offices_phones ON offices(phones)',
  'CREATE INDEX IF NOT EXISTS idx_data_issues_issue_type ON data_issues(issue_type)',
];

Future<void> createOldDatabaseSchema(Database db) async {
  for (final statement in oldDatabaseCreateStatements) {
    await db.execute(statement);
  }
  for (final statement in oldDatabaseIndexStatements) {
    await db.execute(statement);
  }
}
