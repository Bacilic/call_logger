// Οι αλλοιωμένοι χαρακτήρες, άκρη σε άκρη: σάρωση, κατάταξη σε αυτόματη ή
// χειροκίνητη, και εγγραφή στη βάση.
//
//   flutter test test/core/database/old_database/lamp_mixed_script_resolution_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const List<String> _tableStatements = <String>[
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
    phones TEXT
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
    ip_address TEXT,
    network_name TEXT,
    network_source TEXT,
    network_node TEXT,
    network_vlan TEXT,
    network_mac TEXT,
    network_description TEXT,
    network_comments TEXT
  )
  ''',
  // Η ουρά των ευρημάτων: εκεί κάθονται τα προβλήματα ανάμεσα στη σάρωση και
  // στον οδηγό επίλυσης.
  '''
  CREATE TABLE data_issues (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sheet TEXT,
    entity_type TEXT,
    origin TEXT,
    row_number INTEGER,
    column_name TEXT,
    raw_value TEXT,
    issue_type TEXT NOT NULL,
    message TEXT,
    created_at TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open'
  )
  ''',

];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Ο χαλασμένος χαρακτήρας της παλιάς εξαγωγής, ως κωδικός.
  const brokenAnna = 'ʼννα';

  late Directory tempDir;
  late String dbPath;
  late OldEquipmentRepository repository;
  late LampIssueResolutionService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-mixed-script-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    repository = OldEquipmentRepository();
    service = LampIssueResolutionService();

    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      for (final statement in _tableStatements) {
        await db.execute(statement);
      }
      await db.insert('owners', <String, Object?>{
        'owner': 1,
        'last_name': 'Πατσαρίκα',
        // Το όνομα όπως το άφησε η χαλασμένη εξαγωγή.
        'first_name': brokenAnna,
      });
      await db.insert('offices', <String, Object?>{
        'office': 1,
        // Λατινικό «A» στην αρχή ελληνικής λέξης.
        'office_name': 'Aναιμίας',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 100,
        // Λατινικό «O» στο τέλος ελληνικής λέξης.
        'description': 'ΤΟΝΕΡ ΠΛΗΚΤΡΟΛΟΓΙO ΜΑΥΡΟ',
        // Δύο αλφάβητα σε ισοπαλία, και τα δύο εφικτά: χειροκίνητο.
        'comments': 'Oι εκτυπώσεις',
        // Η ωμή τιμή του Excel μένει άθικτη, ό,τι κι αν γράφει.
        'owner_original_text': 'ΠΛΗΚΤΡΟΛΟΓΙO',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 101,
        'description': 'Καθαρή περιγραφή χωρίς πρόβλημα',
        'serial_no': 'GC03320570',
        'attributes': '133MHz 4GB',
      });
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<List<Map<String, Object?>>> scanAndStore() async {
    final scan = await repository.scanIntegrityIssues(dbPath);
    final mixed = scan.issues
        .where((i) => '${i['issue_type']}'.startsWith('mixed_script'))
        .toList();
    await repository.insertDataIssues(dbPath, mixed);
    return mixed;
  }

  Future<Object?> readField(String table, String pk, int id, String column) async {
    await LampDatabaseProvider.instance.close();
    final db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    try {
      final rows = await db.query(
        table,
        columns: <String>[column],
        where: '$pk = ?',
        whereArgs: <Object?>[id],
      );
      return rows.isEmpty ? null : rows.first[column];
    } finally {
      await db.close();
    }
  }

  test('η σάρωση πιάνει τις αλλοιωμένες λέξεις και προσπερνά τις καθαρές', () async {
    final mixed = await scanAndStore();
    final words = mixed.map((i) => i['raw_value']).toSet();

    expect(words, contains(brokenAnna));
    expect(words, contains('Aναιμίας'));
    expect(words, contains('ΠΛΗΚΤΡΟΛΟΓΙO'));
    expect(words, contains('Oι'));
    // Σειριακοί και τεχνικά χαρακτηριστικά δεν είναι ευρήματα.
    expect(words, isNot(contains('GC03320570')));
    expect(words, isNot(contains('133MHz')));
    expect(words, isNot(contains('4GB')));
  });

  test('οι στήλες της ωμής τιμής του Excel δεν σαρώνονται', () async {
    final mixed = await scanAndStore();
    // Η ίδια λέξη υπάρχει και στο owner_original_text του κωδικού 100, αλλά
    // εκεί η αλλοίωση είναι τεκμήριο της εισαγωγής, όχι σφάλμα προς διόρθωση.
    final columns = mixed.map((i) => i['column_name']).toSet();
    expect(columns, isNot(contains('owner_original_text')));
  });

  test('βέβαιη πρόταση κατατάσσεται σε αυτόματη διόρθωση', () async {
    await scanAndStore();
    final proposals = await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.mixedScriptBrokenChar,
    );
    expect(proposals, hasLength(1));
    expect(proposals.single.proposedAction, LampIssueResolutionAction.autoFix);
    expect(proposals.single.proposedMatch, 'Άννα');
  });

  test('αμφίβολη λέξη κατατάσσεται σε χειροκίνητη επισκόπηση', () async {
    await scanAndStore();
    final proposals = await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.mixedScriptAlphabets,
    );
    final doubtful = proposals.where((p) => p.originalValue == 'Oι');
    expect(doubtful, hasLength(1));
    expect(
      doubtful.single.proposedAction,
      LampIssueResolutionAction.manualReview,
    );
    expect(doubtful.single.proposedMatch, isNull);
  });

  test('η αυτόματη διόρθωση γράφει στη βάση και κλείνει το εύρημα', () async {
    await scanAndStore();
    final proposals = <LampIssueResolutionProposal>[
      ...await service.analyzeIssues(
        databasePath: dbPath,
        issueType: LampIssueType.mixedScriptBrokenChar,
      ),
      ...await service.analyzeIssues(
        databasePath: dbPath,
        issueType: LampIssueType.mixedScriptAlphabets,
      ),
    ];
    final auto = proposals
        .where((p) => p.proposedAction == LampIssueResolutionAction.autoFix)
        .map((p) => LampIssueResolutionDecision(proposal: p))
        .toList();
    expect(auto, isNotEmpty);

    final result = await service.applyDecisions(
      databasePath: dbPath,
      decisions: auto,
    );
    expect(result.errors, isEmpty);

    expect(await readField('owners', 'owner', 1, 'first_name'), 'Άννα');
    expect(await readField('offices', 'office', 1, 'office_name'), 'Αναιμίας');
    // Η υπόλοιπη πρόταση μένει άθικτη· αλλάζει μόνο η ύποπτη λέξη.
    expect(
      await readField('equipment', 'code', 100, 'description'),
      'ΤΟΝΕΡ ΠΛΗΚΤΡΟΛΟΓΙΟ ΜΑΥΡΟ',
    );

    // Το αμφίβολο «Oι» παραμένει ανοιχτό: κανείς δεν το έκρινε ακόμη.
    await LampDatabaseProvider.instance.close();
    final db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    final open = await db.rawQuery(
      "SELECT raw_value FROM data_issues "
      "WHERE issue_type LIKE 'mixed_script%' AND COALESCE(status,'open')='open'",
    );
    await db.close();
    expect(open.map((r) => r['raw_value']), contains('Oι'));
  });

  test('χειροκίνητη τιμή του χρήστη γράφεται αντί της πρότασης', () async {
    await scanAndStore();
    final proposals = await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.mixedScriptAlphabets,
    );
    final doubtful = proposals.firstWhere((p) => p.originalValue == 'Oι');
    final manualOption = doubtful.options.firstWhere(
      (o) => o.requiresTextInput,
    );

    final result = await service.applyDecisions(
      databasePath: dbPath,
      decisions: <LampIssueResolutionDecision>[
        LampIssueResolutionDecision(
          proposal: doubtful,
          option: manualOption,
          textInput: 'Οι',
        ),
      ],
    );
    expect(result.errors, isEmpty);
    expect(
      await readField('equipment', 'code', 100, 'comments'),
      'Οι εκτυπώσεις',
    );
  });
}
