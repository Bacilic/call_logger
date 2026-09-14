// Η αποδοχή σειριακού που μοιάζει με επιστημονική μορφή πρέπει να κρατά.
//
// Σενάριο 14/09: ο σειριακός `310128E000079` (κωδικός 1788, EDIMAX THREE
// PORTS) είναι η γνήσια τιμή του κατασκευαστή. Ο ανιχνευτής σφίχτηκε ώστε να
// μην τον πιάνει πια, αλλά κάθε κανόνας βάσει μοτίβου θα έχει κάποτε ψευδώς
// θετικό — και τότε χρειάζεται τρόπος να πει κανείς «αυτό είναι σωστό».
//
// Το λεξιλόγιο υπάρχει ήδη στη βάση (`status = 'accepted'`) και ο σαρωτής το
// σέβεται μόνος του: δεν ξαναγράφει εύρημα με ίδιο κλειδί ταυτότητας,
// ανεξάρτητα από την κατάστασή του.
//
//   flutter test test/core/database/old_database/lamp_accepted_scientific_serial_test.dart

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

  // Γνήσια μορφή υπολογιστικού φύλλου — αυτή θέλουμε να εντοπίζεται.
  const spreadsheetSerial = '4,928E+11';
  const equipmentCode = 1788;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-accepted-sci-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('model', <String, Object?>{
        'model': 79,
        'model_name': '3-ports',
        'category_name': 'Δικτυακά',
      });
      await db.insert('equipment', <String, Object?>{
        'code': equipmentCode,
        'description': 'EDIMAX THREE PORTS',
        'model': 79,
        'serial_no': spreadsheetSerial,
      });
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'serial_scientific_notation',
        'sheet': 'integrity_scan',
        'row_number': equipmentCode,
        'column_name': 'serial_no',
        'raw_value': spreadsheetSerial,
        'message': 'Σειριακός σε επιστημονική μορφή.',
        'status': 'open',
        'created_at': '2026-09-14T12:00:00.000',
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

  Future<void> acceptTheSerial() async {
    final service = LampIssueResolutionService();
    final target = (await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.scientificSerial,
    )).single;
    await service.applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: target,
        option: target.options.firstWhere(
          (o) => o.metadata['operation'] == 'accept_scientific_serial',
        ),
      ),
    );
  }

  test('η αποδοχή προσφέρεται δίπλα στην καταχώρηση νέου σειριακού', () async {
    final service = LampIssueResolutionService();
    final target = (await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.scientificSerial,
    )).single;

    expect(
      target.options.map((o) => o.metadata['operation']),
      containsAll(<String>[
        'reassign_scientific_serial',
        'accept_scientific_serial',
      ]),
      reason: greekExpectMsg(
        'Χωρίς αποδοχή, ένας γνήσιος σειριακός δεν έχει τρόπο να κλείσει — '
        'ή τον αλλοιώνεις ή τον βλέπεις σε κάθε έλεγχο',
      ),
    );
  });

  test('η αποδοχή σημειώνεται και δεν αλλάζει τον σειριακό', () async {
    await acceptTheSerial();

    final issues = await withDb(
      (db) => db.query(
        'data_issues',
        where: 'raw_value = ?',
        whereArgs: [spreadsheetSerial],
      ),
    );
    expect(issues, hasLength(1));
    expect(issues.single['status'], kDataIssueStatusAccepted);
    expect(issues.single['resolution_note'], isNotNull);

    final equipment = await withDb(
      (db) => db.query(
        'equipment',
        columns: <String>['serial_no'],
        where: 'code = ?',
        whereArgs: [equipmentCode],
      ),
    );
    expect(
      equipment.single['serial_no'],
      spreadsheetSerial,
      reason: greekExpectMsg(
        'Η αποδοχή κλείνει το πρόβλημα χωρίς να αγγίξει τα δεδομένα',
      ),
    );
  });

  test(
    'μπαγιάτικο εύρημα φεύγει από τον μετρητή, δεν μένει να λέει ψέματα',
    () async {
      // Ο σειριακός του EDIMAX ήταν καταχωρημένος ως πρόβλημα με τον παλιό,
      // χαλαρό κανόνα. Ο νέος δεν τον πιάνει — αλλά ο μετρητής της οθόνης
      // διαβάζει τα αποθηκευμένα ευρήματα, όχι τον κανόνα. Χωρίς εκκαθάριση, η
      // οθόνη θα έδειχνε «1» και το κουμπί «Επίλυση» θα άνοιγε άδεια λίστα.
      const genuineSerial = '310128E000079';
      await withDb((db) async {
        await db.update(
          'equipment',
          <String, Object?>{'serial_no': genuineSerial},
          where: 'code = ?',
          whereArgs: [equipmentCode],
        );
        await db.update(
          'data_issues',
          <String, Object?>{'raw_value': genuineSerial},
          where: 'raw_value = ?',
          whereArgs: [spreadsheetSerial],
        );
      });

      final repository = OldEquipmentRepository();
      final removed = await repository.dropStaleScientificSerialIssues(dbPath);

      expect(removed, 1);
      final left = await withDb((db) => db.query('data_issues'));
      expect(
        left,
        isEmpty,
        reason: greekExpectMsg(
          'Εύρημα που έπαψε να ισχύει δεν είναι απόφαση ανθρώπου — δεν έχει '
          'αξία ως ιστορικό και δεν επιτρέπεται να φουσκώνει τον μετρητή',
        ),
      );
    },
  );

  test('η εκκαθάριση δεν αγγίζει ό,τι κάποιος δέχτηκε ρητά', () async {
    // Η αποδοχή είναι απόφαση ανθρώπου και είναι το μόνο ίχνος ότι κάποιος
    // ενέκρινε την τιμή. Αν την έσβηνε η εκκαθάριση, ο επόμενος έλεγχος θα
    // ξανάφερνε το ίδιο πρόβλημα σαν να μην είχε αποφασιστεί ποτέ.
    await acceptTheSerial();

    final repository = OldEquipmentRepository();
    final removed = await repository.dropStaleScientificSerialIssues(dbPath);

    expect(removed, 0);
    final rows = await withDb((db) => db.query('data_issues'));
    expect(rows, hasLength(1));
    expect(rows.single['status'], kDataIssueStatusAccepted);
  });
  test('το αποδεκτό δεν ξαναβγαίνει στον επόμενο έλεγχο', () async {
    await acceptTheSerial();

    final service = LampIssueResolutionService();
    final again = await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.scientificSerial,
    );

    expect(
      again,
      isEmpty,
      reason: greekExpectMsg(
        'Αν ξαναβγεί, η αποδοχή δεν σήμαινε τίποτα και ο χρήστης θα την '
        'ξαναπατά σε κάθε έλεγχο',
      ),
    );
  });
}
