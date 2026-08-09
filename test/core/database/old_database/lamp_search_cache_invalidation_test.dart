// Η αναζήτηση της Λάμπας δουλεύει πάνω σε αντίγραφο της βάσης στη μνήμη.
//
// Σενάριο 09/08: ο χρήστης έλυσε πέντε διπλότυπα πάγια. Η βάση καθάρισε —
// το πάγιο 903 έμεινε μόνο στον εξοπλισμό 2351 — αλλά η αναζήτηση συνέχιζε
// να δείχνει δύο εγγραφές. Το αντίγραφο είχε τραβηχτεί πριν την επίλυση και
// κανείς δεν το ακύρωσε: μόνο η χειροκίνητη επεξεργασία εγγραφής και το
// κουμπί «Ανανέωση αναζήτησης» το έκαναν.
//
// Το συμβόλαιο: ό,τι γράφει στη βάση, ακυρώνει το αντίγραφο.
//
//   flutter test test/core/database/old_database/lamp_search_cache_invalidation_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/core/database/lamp_migration_service.dart';
import 'package:call_logger/core/database/old_database/lamp_network_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/lamp_settings_store.dart';
import 'package:call_logger/core/database/old_database/old_excel_importer.dart';
import 'package:call_logger/core/database/old_database/old_equipment_repository.dart';
import 'package:call_logger/features/lamp/controllers/lamp_screen_host.dart';
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
    tempDir = await Directory.systemTemp.createTemp('lamp-search-cache-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      // Δύο εξοπλισμοί με το ίδιο πάγιο — το σενάριο πριν την επίλυση.
      await db.insert('equipment', <String, Object?>{
        'code': 2351,
        'description': 'Switch Enterasys 08G20G4-24',
        'asset_no': '903',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 3790,
        'description': 'SWITCH ENTERASYS 08G20G4-24',
        'asset_no': '903',
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

  Future<int> searchAssetHits(OldEquipmentRepository repository) async {
    final result = await repository.globalSearch(dbPath, '903', maxDisplay: 50);
    return result.rows.length;
  }

  /// Σβήνει το πάγιο του 3790 απευθείας, όπως κάνει η επίλυση διπλοτύπων.
  Future<void> clearDuplicateAsset() async {
    await LampDatabaseProvider.instance.close();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.update(
        'equipment',
        <String, Object?>{'asset_no': null},
        where: 'code = 3790',
      );
    } finally {
      await db.close();
    }
  }

  test('χωρίς ακύρωση η αναζήτηση δείχνει το παλιό στιγμιότυπο', () async {
    final repository = OldEquipmentRepository();

    expect(await searchAssetHits(repository), 2);
    await clearDuplicateAsset();

    expect(
      await searchAssetHits(repository),
      2,
      reason: greekExpectMsg(
        'Αυτή είναι η συμπεριφορά που μπέρδεψε τον χρήστη· το τεστ την '
        'καταγράφει ώστε να φαίνεται τι ακριβώς διορθώνει η ακύρωση',
      ),
    );
  });

  test('η ακύρωση φέρνει την αναζήτηση στην πραγματικότητα', () async {
    final repository = OldEquipmentRepository();

    expect(await searchAssetHits(repository), 2);
    await clearDuplicateAsset();
    repository.invalidateSearchCache(dbPath);

    expect(
      await searchAssetHits(repository),
      1,
      reason: greekExpectMsg(
        'Μετά την επίλυση το πάγιο 903 ανήκει μόνο στον 2351 — η αναζήτηση '
        'πρέπει να λέει το ίδιο με τη βάση',
      ),
    );
  });

  test('και οι δύο υπηρεσίες επίλυσης είναι συνδεδεμένες', () {
    final repository = OldEquipmentRepository();
    final issues = LampIssueResolutionService();
    final network = LampNetworkIssueResolutionService();
    LampScreenShared(
      settings: LampSettingsStore(),
      repository: repository,
      issueResolutionService: issues,
      networkIssueResolutionService: network,
      migrationService: LampMigrationService(),
      importer: OldExcelImporter(),
    );

    expect(issues.onDatabaseChanged, isNotNull);
    expect(
      network.onDatabaseChanged,
      isNotNull,
      reason: greekExpectMsg(
        'Και η επίλυση δικτύου γράφει σε εξοπλισμό· αν μείνει ασύνδετη, το '
        'ίδιο σφάλμα επιστρέφει από άλλη πόρτα',
      ),
    );
  });

  test('η επίλυση ακυρώνει το αντίγραφο μόνη της', () async {
    final repository = OldEquipmentRepository();
    final service = LampIssueResolutionService();
    // Η σύνδεση γίνεται μία φορά, εκεί που στήνονται τα κοινά αντικείμενα
    // της οθόνης — όχι σε κάθε καλούντα ξεχωριστά.
    LampScreenShared(
      settings: LampSettingsStore(),
      repository: repository,
      issueResolutionService: service,
      networkIssueResolutionService: LampNetworkIssueResolutionService(),
      migrationService: LampMigrationService(),
      importer: OldExcelImporter(),
    );

    expect(await searchAssetHits(repository), 2);

    await LampDatabaseProvider.instance.close();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'duplicate_asset_no',
        'sheet': 'integrity_scan',
        'row_number': 2351,
        'column_name': 'asset_no',
        'raw_value': '903',
        'status': 'open',
        'created_at': '2026-08-09T10:00:00.000',
      });
    } finally {
      await db.close();
    }

    final proposal = (await service.analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.duplicateAssetNo,
    )).single;
    await service.applySingleDecision(
      databasePath: dbPath,
      decision: LampIssueResolutionDecision(
        proposal: proposal,
        option: proposal.options.firstWhere(
          (o) =>
              o.metadata['duplicateActionKind'] == 'clear' &&
              o.metadata['keepCode'] == 2351,
        ),
      ),
    );

    expect(
      await searchAssetHits(repository),
      1,
      reason: greekExpectMsg(
        'Ο οδηγός αλλάζει δεκάδες εγγραφές· αν δεν ακυρώνει το αντίγραφο, '
        'ο χρήστης βλέπει λυμένα προβλήματα σαν να υπάρχουν ακόμη',
      ),
    );
  });
}
