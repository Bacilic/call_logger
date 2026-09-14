// Ο κατάλογος προβλημάτων της Λάμπας είναι εικόνα της βάσης ΤΩΡΑ.
//
// Σενάριο 14/09: ο σειριακός `310128E000079` (κωδικός 1788) αποδείχθηκε
// γνήσιος και ο ανιχνευτής σφίχτηκε ώστε να μην τον πιάνει. Το αποθηκευμένο
// εύρημα όμως έμενε: ο σαρωτής μόνο πρόσθετε. Η οθόνη μετρούσε 315 ενώ η βάση
// είχε 314, και ο οδηγός επίλυσης απαντούσε «δεν υπάρχουν προτάσεις» χωρίς να
// καθαρίζει τίποτα.
//
// Συμβόλαιο: όποιος έλεγχος αποδεικνύει ότι ένα εύρημα έπαψε να ισχύει, το
// αφαιρεί — μέσα σε τρεις φρουρούς που δεν είναι διακοσμητικοί.
//
//   flutter test test/core/database/old_database/lamp_stale_integrity_issues_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late OldEquipmentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-stale-issues-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
    } finally {
      await db.close();
    }
    repository = OldEquipmentRepository();
    // Οι στήλες `entity_type`, `origin` και `status` δεν είναι στο αρχικό
    // σχήμα — τις προσθέτει το repository στην πρώτη επαφή του με τον πίνακα.
    // Ένα ανώδυνο διάβασμα εδώ στήνει τη βάση όπως την ξέρει η εφαρμογή.
    await repository.dataIssues(dbPath);
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<T> withDb<T>(Future<T> Function(Database db) action) async {
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      return await action(db);
    } finally {
      await db.close();
    }
  }

  /// Γράφει ένα εύρημα όπως ακριβώς το γράφει ο σαρωτής.
  Future<void> storeIssue({
    required String issueType,
    required int rowNumber,
    required String rawValue,
    String column = 'serial_no',
    String origin = 'integrity_scan',
    String status = 'open',
  }) async {
    await withDb(
      (db) => db.insert('data_issues', <String, Object?>{
        'issue_type': issueType,
        'sheet': 'integrity_scan',
        'entity_type': 'equipment',
        'origin': origin,
        'row_number': rowNumber,
        'column_name': column,
        'raw_value': rawValue,
        'message': 'δοκιμαστικό εύρημα',
        'status': status,
        'created_at': '2026-09-14T12:00:00.000',
      }),
    );
  }

  /// Ένα φρέσκο εύρημα στη μορφή που επιστρέφει η σάρωση.
  Map<String, Object?> freshIssue({
    required String issueType,
    required int rowNumber,
    required String rawValue,
    String column = 'serial_no',
  }) {
    return <String, Object?>{
      'issue_type': issueType,
      'sheet': 'equipment',
      'entity_type': 'equipment',
      'origin': 'integrity_scan',
      'row_number': rowNumber,
      'column_name': column,
      'raw_value': rawValue,
      'message': 'δοκιμαστικό εύρημα',
      'created_at': '2026-09-14T12:00:00.000',
    };
  }

  Future<int> openCount() async {
    final rows = await withDb(
      (db) => db.rawQuery(
        "SELECT COUNT(*) AS c FROM data_issues WHERE COALESCE(status,'open') = 'open'",
      ),
    );
    return rows.first['c']! as int;
  }

  test('εύρημα που δεν αναπαράγεται πια φεύγει από τον κατάλογο', () async {
    await storeIssue(
      issueType: 'serial_scientific_notation',
      rowNumber: 1788,
      rawValue: '310128E000079',
    );

    final removed = await repository.dropStaleIntegrityIssues(
      dbPath,
      checkedIssueTypes: const <String>{'serial_scientific_notation'},
      freshIssues: const <Map<String, Object?>>[],
    );

    expect(removed, 1);
    expect(await openCount(), 0);
  });

  test('εύρημα που η σάρωση ξαναβρήκε παραμένει άθικτο', () async {
    await storeIssue(
      issueType: 'duplicate_asset_no',
      rowNumber: 42,
      rawValue: 'A-1000',
      column: 'asset_no',
    );

    final removed = await repository.dropStaleIntegrityIssues(
      dbPath,
      checkedIssueTypes: const <String>{'duplicate_asset_no'},
      freshIssues: <Map<String, Object?>>[
        freshIssue(
          issueType: 'duplicate_asset_no',
          rowNumber: 42,
          rawValue: 'A-1000',
          column: 'asset_no',
        ),
      ],
    );

    expect(removed, 0);
    expect(await openCount(), 1);
  });

  test(
    'είδος που ΔΕΝ ελέγχθηκε δεν αγγίζεται — η σιωπή δεν είναι απόδειξη',
    () async {
      // Το βήμα ακυρώθηκε ή έσκασε, άρα δεν έχει γνώμη για αυτό το είδος.
      await storeIssue(
        issueType: 'set_master_cycle',
        rowNumber: 7,
        rawValue: '7',
        column: 'set_master',
      );

      final removed = await repository.dropStaleIntegrityIssues(
        dbPath,
        checkedIssueTypes: const <String>{'duplicate_asset_no'},
        freshIssues: const <Map<String, Object?>>[],
      );

      expect(removed, 0);
      expect(await openCount(), 1);
    },
  );

  test(
    'εύρημα χειροκίνητο ή από εισαγωγή Excel δεν ανήκει στη σάρωση',
    () async {
      await storeIssue(
        issueType: 'serial_scientific_notation',
        rowNumber: 1788,
        rawValue: '310128E000079',
        origin: 'manual',
      );

      final removed = await repository.dropStaleIntegrityIssues(
        dbPath,
        checkedIssueTypes: const <String>{'serial_scientific_notation'},
        freshIssues: const <Map<String, Object?>>[],
      );

      expect(
        removed,
        0,
        reason: 'Η σάρωση δεν το γέννησε, άρα δεν της ανήκει να το σβήσει',
      );
    },
  );

  test(
    'η αποδοχή και η αναβολή είναι αποφάσεις ανθρώπου και επιβιώνουν',
    () async {
      await storeIssue(
        issueType: 'serial_scientific_notation',
        rowNumber: 1788,
        rawValue: '310128E000079',
        status: kDataIssueStatusAccepted,
      );
      await storeIssue(
        issueType: 'serial_scientific_notation',
        rowNumber: 1789,
        rawValue: '410128E000079',
        status: kDataIssueStatusDeferred,
      );

      final removed = await repository.dropStaleIntegrityIssues(
        dbPath,
        checkedIssueTypes: const <String>{'serial_scientific_notation'},
        freshIssues: const <Map<String, Object?>>[],
      );

      expect(removed, 0);
      final rows = await withDb((db) => db.query('data_issues'));
      expect(rows, hasLength(2));
    },
  );

  test('τα ευρήματα κλειδιών αναφοράς ΔΕΝ δηλώνονται ποτέ ελεγμένα', () async {
    // Ο φρουρός που προστατεύει 212 αληθινά ευρήματα στη ζωντανή βάση.
    //
    // Το βήμα των κλειδιών ομαδοποιεί ανά κακή τιμή και εξαιρεί ρητά ό,τι
    // έχει ήδη καταγραφεί, οπότε η έξοδός του είναι «μόνο τα νέα» — ποτέ
    // πλήρης εικόνα. Αν δήλωνε τα είδη του ως ελεγμένα, η πρώτη κιόλας
    // σάρωση θα έσβηνε ΚΑΘΕ υπάρχον εύρημα κλειδιού ως δήθεν ξεπερασμένο.
    final scan = await repository.scanIntegrityIssues(dbPath);

    expect(
      scan.checkedIssueTypes,
      isNot(contains('non_numeric_fk')),
      reason: 'Η έξοδος του βήματος δεν είναι πλήρης εικόνα',
    );
    expect(scan.checkedIssueTypes, isNot(contains('unknown_id')));
    expect(
      scan.checkedIssueTypes,
      containsAll(<String>[
        'duplicate_asset_no',
        'duplicate_model_serial',
        'serial_scientific_notation',
        'set_master_self_reference',
        'set_master_missing_target',
        'set_master_cycle',
        'network_duplicate_name',
        'mixed_script_alphabets',
      ]),
      reason: 'Τα υπόλοιπα βήματα επιστρέφουν ό,τι βρίσκουν, χωρίς φίλτρο',
    );
  });

  test('χωρίς κανένα ελεγμένο είδος, δεν σβήνεται τίποτα', () async {
    await storeIssue(
      issueType: 'serial_scientific_notation',
      rowNumber: 1788,
      rawValue: '310128E000079',
    );

    final removed = await repository.dropStaleIntegrityIssues(
      dbPath,
      checkedIssueTypes: const <String>{},
      freshIssues: const <Map<String, Object?>>[],
    );

    expect(removed, 0);
    expect(await openCount(), 1);
  });
}
