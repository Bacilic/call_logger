// Η αποδοχή διπλότυπου σειριακού πρέπει να κρατά.
//
// Σενάριο 09/08: ο χρήστης δέχτηκε το κλειδί Windows
// `RBJ6D-8BKW9-MCWC8-6DQJ8-Y2JV7` (13 μηχανήματα) ως σωστό. Ο επόμενος
// έλεγχος ακεραιότητας το ξαναέφερε ως πρόβλημα.
//
// Η αιτία: η αποδοχή **διέγραφε** την εκκρεμότητα. Τα διπλότυπα όμως
// παραμένουν επίτηδες, οπότε ο έλεγχος τα ξαναβρίσκει και δεν έχει τρόπο να
// ξέρει ότι κάποιος τα ενέκρινε. Η βάση έχει ήδη λεξιλόγιο γι' αυτό —
// `status = 'accepted'` — και ο έλεγχος το σέβεται, γιατί συγκρίνει με
// **όλες** τις εγγραφές, όχι μόνο τις ανοιχτές.
//
//   flutter test test/core/database/old_database/lamp_accepted_duplicate_persists_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_reporter.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const licenseKey = 'RBJ6D-8BKW9-MCWC8-6DQJ8-Y2JV7';

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-accepted-dup-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('model', <String, Object?>{
        'model': 410,
        'model_name': 'Windows 7 Pro',
        'category_name': 'Λογισμικό',
      });
      for (final code in <int>[2449, 2472, 2581]) {
        await db.insert('equipment', <String, Object?>{
          'code': code,
          'description': 'Windows 7 Pro 64bit',
          'model': 410,
          'serial_no': licenseKey,
        });
      }
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'duplicate_model_serial',
        'sheet': 'integrity_scan',
        'column_name': 'serial_no',
        'raw_value': licenseKey,
        'message': 'Διπλότυπος συνδυασμός μοντέλου/σειριακού.',
        'status': 'open',
        'created_at': '2026-08-09T12:19:21.000',
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

  Future<void> acceptTheDuplicate() async {
    final service = LampIssueResolutionService();
    final target = (await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.duplicateModelSerial,
    )).single;
    await service.applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: target.options.firstWhere(
          (o) => o.metadata['operation'] == 'accept_duplicate_serial',
        ),
      ),
    );
  }

  test('η αποδοχή σημειώνεται, δεν σβήνεται', () async {
    await acceptTheDuplicate();

    final rows = await withDb(
      (db) => db.query('data_issues', where: 'raw_value = ?', whereArgs: [licenseKey]),
    );

    expect(
      rows,
      hasLength(1),
      reason: greekExpectMsg(
        'Διαγραμμένη εκκρεμότητα δεν αφήνει ίχνος· ο επόμενος έλεγχος '
        'ξαναβρίσκει τα διπλότυπα και δεν ξέρει ότι εγκρίθηκαν',
      ),
    );
    expect(rows.single['status'], kDataIssueStatusAccepted);
    expect(rows.single['resolution_note'], isNotNull);
  });

  test('το αποδεκτό δεν εμφανίζεται πια ως ανοικτό', () async {
    await acceptTheDuplicate();

    expect(
      await withDb((db) => db.query('data_issues', where: "status = 'open'")),
      isEmpty,
    );
    expect(
      await LampIssueResolutionService().analyzeIssues(
        databasePath: dbPath,
        issueType: LampIssueType.duplicateModelSerial,
      ),
      isEmpty,
      reason: greekExpectMsg(
        'Ο οδηγός δεν πρέπει να ξαναρωτά για κάτι που ο χρήστης ενέκρινε',
      ),
    );
  });

  test('ο έλεγχος ακεραιότητας δεν το ξαναφέρνει', () async {
    await acceptTheDuplicate();

    final scan = await OldEquipmentRepository().scanIntegrityIssues(dbPath);
    final fresh = await OldEquipmentRepository().filterToNewDataIssuesOnly(
      dbPath,
      scan.issues,
    );

    expect(
      fresh.where((i) => i['raw_value'] == licenseKey),
      isEmpty,
      reason: greekExpectMsg(
        'Αυτό ακριβώς έβλεπε ο χρήστης: δεχόταν το κλειδί και ο επόμενος '
        'έλεγχος το ξαναέφερνε',
      ),
    );
  });

  test('τα δεδομένα μένουν άθικτα', () async {
    await acceptTheDuplicate();

    final serials = await withDb(
      (db) => db.query('equipment', columns: <String>['serial_no']),
    );

    expect(
      serials.map((r) => r['serial_no']),
      everyElement(licenseKey),
      reason: greekExpectMsg(
        'Η αποδοχή δηλώνει ότι η επανάληψη είναι σωστή — δεν αλλάζει τίποτα',
      ),
    );
  });
}
