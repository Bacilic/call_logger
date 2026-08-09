// Δημιουργία σύμβασης που δεν υπάρχει στη βάση.
//
// Οι τιμές που ήρθαν από το Excel δείχνουν κάποτε σε συμβάσεις που ποτέ δεν
// καταχωρήθηκαν. Ο οδηγός πρόσφερε μόνο επανασύνδεση με υπάρχουσες, οπότε
// δεν υπήρχε σωστή απάντηση.
//
// Ο προμηθευτής και η κατηγορία διαλέγονται από τους υπάρχοντες: η Λάμπα δεν
// έχει χωριστούς πίνακες γι' αυτούς και ελεύθερο κείμενο θα δημιουργούσε
// δεύτερη ορθογραφία του ίδιου προμηθευτή.
//
//   flutter test test/core/database/old_database/lamp_create_contract_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_reporter.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-create-contract-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('contracts', <String, Object?>{
        'contract': 3,
        'contract_name': '17995/14-11-2000',
        'supplier': 5,
        'supplier_name': 'Infotechnica SA',
        'category': 1,
        'category_name': 'Προμήθεια',
      });
      await db.insert('contracts', <String, Object?>{
        'contract': 7,
        'contract_name': '4307/23-7-1997',
        'supplier': 42,
        'supplier_name': 'MULTILAB AE',
        'category': 2,
        'category_name': 'Δωρεά',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 5099,
        'description': 'Cisco Switch',
        'contract_original_text': '44444',
      });
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'unknown_id',
        'sheet': 'integrity_scan',
        'row_number': 5099,
        'column_name': 'contract',
        'raw_value': '44444',
        'status': 'open',
        'created_at': '2026-08-09T10:00:00.000',
      });
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<T> withDb<T>(Future<T> Function(Database db) action) async {
    await LampDatabaseProvider.instance.close();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      return await action(db);
    } finally {
      await db.close();
    }
  }

  Future<LampIssueResolutionProposal> proposal() async {
    return (await LampIssueResolutionService().analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.unknownId,
    )).single;
  }

  test('η επιλογή δημιουργίας υπάρχει και προτείνει την ωμή τιμή ως όνομα', () async {
    final option = (await proposal()).options.firstWhere(
      (o) => o.requiresContractInput,
    );

    expect(option.metadata['createContractName'], '44444');
    expect(option.label, contains('44444'));
  });

  test('ο κατάλογος φέρνει τους υπάρχοντες προμηθευτές και κατηγορίες', () async {
    final catalog = await LampIssueResolutionService().loadPlacementCatalog(
      databasePath: dbPath,
    );

    expect(catalog.suppliers.map((s) => s.name), containsAll(<String>[
      'Infotechnica SA',
      'MULTILAB AE',
    ]));
    expect(catalog.contractCategories.map((c) => c.name), containsAll(<String>[
      'Προμήθεια',
      'Δωρεά',
    ]));
    expect(
      catalog.searchSuppliers('multi').single.id,
      42,
      reason: greekExpectMsg(
        'Χωρίς αναζήτηση ο χρήστης θα κυλούσε λίστα 77 προμηθευτών',
      ),
    );
  });

  test('η δημιουργία γράφει σύμβαση, προμηθευτή και συνδέει τον εξοπλισμό', () async {
    final target = await proposal();
    final service = LampIssueResolutionService();

    await service.applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: target.options.firstWhere((o) => o.requiresContractInput),
        contractInput: const LampContractInput(
          name: '44444 09/08/2026',
          supplierId: 42,
          categoryId: 2,
        ),
      ),
    );

    final created = await withDb(
      (db) async => (await db.query(
        'contracts',
        where: "contract_name = '44444 09/08/2026'",
      )).single,
    );

    expect(created['supplier'], 42);
    expect(
      created['supplier_name'],
      'MULTILAB AE',
      reason: greekExpectMsg(
        'Το όνομα διαβάζεται από τα υπάρχοντα ζεύγη, ώστε ο ίδιος '
        'προμηθευτής να μη γραφτεί με δύο ορθογραφίες',
      ),
    );
    expect(created['category'], 2);
    expect(created['category_name'], 'Δωρεά');

    final equipment = await withDb(
      (db) async => (await db.query(
        'equipment',
        where: 'code = 5099',
      )).single,
    );
    expect(equipment['contract'], created['contract']);
    expect(equipment['contract_original_text'], isNull);

    final open = await withDb(
      (db) async => db.query('data_issues', where: "status = 'open'"),
    );
    expect(open, isEmpty);
  });

  test('σύμβαση χωρίς προμηθευτή επιτρέπεται', () async {
    final target = await proposal();

    await LampIssueResolutionService().applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: target.options.firstWhere((o) => o.requiresContractInput),
        contractInput: const LampContractInput(name: '44444'),
      ),
    );

    final created = await withDb(
      (db) async =>
          (await db.query('contracts', where: "contract_name = '44444'")).single,
    );

    expect(created['supplier'], isNull);
    expect(
      created['supplier_name'],
      isNull,
      reason: greekExpectMsg(
        'Ο προμηθευτής δεν είναι πάντα γνωστός· η σύμβαση καταχωρείται και '
        'συμπληρώνεται αργότερα',
      ),
    );
  });

  test('χωρίς όνομα η δημιουργία απορρίπτεται', () async {
    final target = await proposal();

    final result = await LampIssueResolutionService().applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: target.options.firstWhere((o) => o.requiresContractInput),
        contractInput: const LampContractInput(name: '   '),
      ),
    );

    expect(result.unresolved, 1);
    final contracts = await withDb((db) async => db.query('contracts'));
    expect(
      contracts,
      hasLength(2),
      reason: greekExpectMsg(
        'Ανώνυμη σύμβαση είναι σκουπίδι στη βάση — καλύτερα να αποτύχει '
        'η ενέργεια',
      ),
    );
  });
}
