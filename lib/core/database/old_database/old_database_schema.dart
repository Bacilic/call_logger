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
      ON DELETE RESTRICT ON UPDATE CASCADE
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
    FOREIGN KEY (model) REFERENCES model(model)
      ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (contract) REFERENCES contracts(contract)
      ON DELETE SET NULL ON UPDATE CASCADE,
    FOREIGN KEY (owner) REFERENCES owners(owner)
      ON DELETE SET NULL ON UPDATE CASCADE,
    FOREIGN KEY (office) REFERENCES offices(office)
      ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (set_master) REFERENCES equipment(code)
      ON DELETE RESTRICT ON UPDATE CASCADE
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

const List<String> oldDatabaseIntegrityStatements = <String>[
  '''
  CREATE UNIQUE INDEX IF NOT EXISTS ux_equipment_asset_no_clean
  ON equipment(asset_no)
  WHERE asset_no IS NOT NULL AND TRIM(asset_no) <> ''
  ''',
  '''
  CREATE UNIQUE INDEX IF NOT EXISTS ux_equipment_model_serial_no_clean
  ON equipment(model, serial_no)
  WHERE model IS NOT NULL AND serial_no IS NOT NULL AND TRIM(serial_no) <> ''
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_equipment_set_master_no_self_insert
  BEFORE INSERT ON equipment
  WHEN NEW.set_master IS NOT NULL AND NEW.set_master = NEW.code
  BEGIN
    SELECT RAISE(ABORT, 'Το set_master δεν μπορεί να δείχνει στον ίδιο εξοπλισμό.');
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_equipment_set_master_no_self_update
  BEFORE UPDATE OF code, set_master ON equipment
  WHEN NEW.set_master IS NOT NULL AND NEW.set_master = NEW.code
  BEGIN
    SELECT RAISE(ABORT, 'Το set_master δεν μπορεί να δείχνει στον ίδιο εξοπλισμό.');
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_equipment_set_master_no_cycle_insert
  BEFORE INSERT ON equipment
  WHEN NEW.set_master IS NOT NULL
  BEGIN
    SELECT RAISE(ABORT, 'Η ιεραρχία set_master δημιουργεί κύκλο.')
    WHERE EXISTS (
      WITH RECURSIVE chain(code) AS (
        SELECT NEW.set_master
        UNION ALL
        SELECT e.set_master
        FROM equipment e
        JOIN chain ON e.code = chain.code
        WHERE e.set_master IS NOT NULL
      )
      SELECT 1 FROM chain WHERE code = NEW.code
    );
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_equipment_set_master_no_cycle_update
  BEFORE UPDATE OF code, set_master ON equipment
  WHEN NEW.set_master IS NOT NULL
  BEGIN
    SELECT RAISE(ABORT, 'Η ιεραρχία set_master δημιουργεί κύκλο.')
    WHERE EXISTS (
      WITH RECURSIVE chain(code) AS (
        SELECT NEW.set_master
        UNION ALL
        SELECT e.set_master
        FROM equipment e
        JOIN chain ON e.code = chain.code
        WHERE e.set_master IS NOT NULL
      )
      SELECT 1 FROM chain WHERE code = NEW.code
    );
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_equipment_owner_office_match_insert
  BEFORE INSERT ON equipment
  WHEN NEW.owner IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM owners o
      WHERE o.owner = NEW.owner
        AND (o.office IS NOT NEW.office)
    )
  BEGIN
    SELECT RAISE(ABORT, 'Το γραφείο του εξοπλισμού πρέπει να ταιριάζει με το γραφείο του κατόχου.');
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_equipment_owner_office_match_update
  BEFORE UPDATE OF owner, office ON equipment
  WHEN NEW.owner IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM owners o
      WHERE o.owner = NEW.owner
        AND (o.office IS NOT NEW.office)
    )
  BEGIN
    SELECT RAISE(ABORT, 'Το γραφείο του εξοπλισμού πρέπει να ταιριάζει με το γραφείο του κατόχου.');
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_offices_restrict_delete
  BEFORE DELETE ON offices
  WHEN EXISTS (SELECT 1 FROM owners WHERE office = OLD.office)
    OR EXISTS (SELECT 1 FROM equipment WHERE office = OLD.office)
  BEGIN
    SELECT RAISE(ABORT, 'Δεν μπορεί να διαγραφεί γραφείο που χρησιμοποιείται από ιδιοκτήτες ή εξοπλισμό.');
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_model_restrict_delete
  BEFORE DELETE ON model
  WHEN EXISTS (SELECT 1 FROM equipment WHERE model = OLD.model)
  BEGIN
    SELECT RAISE(ABORT, 'Δεν μπορεί να διαγραφεί μοντέλο που χρησιμοποιείται από εξοπλισμό.');
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_equipment_master_restrict_delete
  BEFORE DELETE ON equipment
  WHEN EXISTS (SELECT 1 FROM equipment WHERE set_master = OLD.code)
  BEGIN
    SELECT RAISE(ABORT, 'Δεν μπορεί να διαγραφεί master εξοπλισμός πριν αποσυνδεθούν τα παιδιά του.');
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_contracts_delete_set_null
  BEFORE DELETE ON contracts
  BEGIN
    UPDATE equipment SET contract = NULL WHERE contract = OLD.contract;
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_owners_delete_set_null
  BEFORE DELETE ON owners
  BEGIN
    UPDATE equipment SET owner = NULL WHERE owner = OLD.owner;
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_offices_update_cascade
  AFTER UPDATE OF office ON offices
  WHEN NEW.office IS NOT OLD.office
  BEGIN
    UPDATE owners SET office = NEW.office WHERE office = OLD.office;
    UPDATE equipment SET office = NEW.office WHERE office = OLD.office;
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_owners_update_cascade
  AFTER UPDATE OF owner ON owners
  WHEN NEW.owner IS NOT OLD.owner
  BEGIN
    UPDATE equipment SET owner = NEW.owner WHERE owner = OLD.owner;
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_model_update_cascade
  AFTER UPDATE OF model ON model
  WHEN NEW.model IS NOT OLD.model
  BEGIN
    UPDATE equipment SET model = NEW.model WHERE model = OLD.model;
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_contracts_update_cascade
  AFTER UPDATE OF contract ON contracts
  WHEN NEW.contract IS NOT OLD.contract
  BEGIN
    UPDATE equipment SET contract = NEW.contract WHERE contract = OLD.contract;
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS trg_equipment_code_update_cascade
  AFTER UPDATE OF code ON equipment
  WHEN NEW.code IS NOT OLD.code
  BEGIN
    UPDATE equipment SET set_master = NEW.code WHERE set_master = OLD.code;
  END
  ''',
];

Future<void> createOldDatabaseSchema(Database db) async {
  for (final statement in oldDatabaseCreateStatements) {
    await db.execute(statement);
  }
  for (final statement in oldDatabaseIndexStatements) {
    await db.execute(statement);
  }
  await createOldDatabaseIntegrityArtifacts(db);
}

Future<void> createOldDatabaseIntegrityArtifacts(Database db) async {
  for (final statement in oldDatabaseIntegrityStatements) {
    await db.execute(statement);
  }
}
