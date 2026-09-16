// Μία εκκίνηση = ΜΙΑ επίλυση διαδρομής.
//
// Ο έλεγχος εκκίνησης επέλυε τη διαδρομή και αμέσως μετά το άνοιγμα της βάσης
// την ξαναεπέλυε από την αρχή — ίδια ρύθμιση, ίδιο αρχείο, ίδια απάντηση. Σε
// δικτυακή διαδρομή που δεν απαντά, η αναζήτηση του αρχείου έχει όριο δύο
// δευτερολέπτων, οπότε η διπλή δουλειά γινόταν διπλή αναμονή.
//
//   flutter test test/core/database/database_path_resolution_once_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/database/database_path_resolution.dart';
import 'package:call_logger/core/init/startup_engine_failure.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/services/startup_asset_integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

/// Φάκελος πόρων χωρίς ελλείψεις, ώστε ο δομικός έλεγχος να μη χρωματίσει το
/// αποτέλεσμα: εδώ μας ενδιαφέρει η διαδρομή, όχι τα αρχεία της εφαρμογής.
Future<String> _createHealthyFlutterAssets(Directory root) async {
  final assets = Directory(p.join(root.path, 'flutter_assets'));
  await Directory(p.join(assets.path, 'fonts')).create(recursive: true);
  await Directory(p.join(assets.path, 'assets')).create(recursive: true);
  await File(p.join(assets.path, 'FontManifest.json')).writeAsString('[]');
  await File(p.join(assets.path, 'AssetManifest.bin')).writeAsBytes(const [0]);
  final cupertino = File(
    p.join(
      assets.path,
      'packages',
      'cupertino_icons',
      'assets',
      'CupertinoIcons.ttf',
    ),
  );
  await cupertino.parent.create(recursive: true);
  await cupertino.writeAsBytes(const [0]);
  return assets.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late String assetsPath;
  late String dbPath;

  setUp(() async {
    clearStartupEngineFailure();
    initSqfliteFfiForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();
    tempRoot = await Directory.systemTemp.createTemp('path_resolution_once_');
    assetsPath = await _createHealthyFlutterAssets(tempRoot);
    dbPath = p.join(tempRoot.path, 'once.db');
    await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
    await DatabaseHelper.instance.closeConnection();
    await SettingsService().setDatabasePath(dbPath);
    debugDatabasePathResolutionCount = 0;
  });

  tearDown(() async {
    clearStartupEngineFailure();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('οι έλεγχοι εκκίνησης επιλύουν τη διαδρομή ΜΙΑ φορά, όχι δύο', () async {
    final runner = await runDatabaseInitChecks(
      assetIntegrity: StartupAssetIntegrityService(
        flutterAssetsDirectory: assetsPath,
      ),
    );

    // Χωρίς αυτό το τεστ θα περνούσε και με κλειστή βάση: η επίλυση του
    // ανοίγματος είναι ακριβώς εκείνη που μετράμε ότι δεν ξαναγίνεται.
    expect(
      runner.result.isSuccess,
      isTrue,
      reason: 'η βάση πρέπει όντως να άνοιξε: ${runner.result.message}',
    );
    expect(
      debugDatabasePathResolutionCount,
      1,
      reason: 'ο έλεγχος και το άνοιγμα μοιράζονται την ίδια επίλυση',
    );
  });

  test('έξω από τους ελέγχους, το άνοιγμα επιλύει μόνο του', () async {
    await runDatabaseInitChecks(
      assetIntegrity: StartupAssetIntegrityService(
        flutterAssetsDirectory: assetsPath,
      ),
    );
    await DatabaseHelper.instance.closeConnection();
    debugDatabasePathResolutionCount = 0;

    // Ο φρουρός μένει: ένα ανεξάρτητο άνοιγμα (αλλαγή βάσης, επαναδοκιμή,
    // τεμπέλικη πρόσβαση από repository) δεν έχει κανέναν να το προμηθεύσει.
    await DatabaseHelper.instance.initializeDatabase();

    expect(debugDatabasePathResolutionCount, 1);
  });
}
