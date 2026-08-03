// Ο δομικός έλεγχος αρχείων προηγείται των ελέγχων βάσης και προηγείται
// στην αναφορά όταν αποτυγχάνει και η βάση.
//
//   flutter test test/core/database/database_init_structural_order_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_runner.dart';
import 'package:call_logger/core/init/startup_engine_failure.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/services/startup_asset_integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

/// Δημιουργεί φάκελο `flutter_assets` με προαιρετική ζημιά στις γραμματοσειρές.
Future<String> _createFlutterAssets(
  Directory root, {
  required bool withFonts,
}) async {
  final assets = Directory(p.join(root.path, 'flutter_assets'));
  await assets.create(recursive: true);
  if (withFonts) {
    await Directory(p.join(assets.path, 'fonts')).create(recursive: true);
  }
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

  setUp(() async {
    clearStartupEngineFailure();
    initSqfliteFfiForTests();
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    forgetDatabaseInitResult();
    tempRoot = await Directory.systemTemp.createTemp('structural_order_');
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

  test(
    'βάση που λείπει + ελλιπή αρχεία → τα αρχεία πρώτα, η βάση δεύτερη',
    () async {
      final assetsPath = await _createFlutterAssets(
        tempRoot,
        withFonts: false,
      );
      await SettingsService().setDatabasePath(
        p.join(tempRoot.path, 'δεν_υπάρχει.db'),
      );

      final runnerResult = await runDatabaseInitChecks(
        assetIntegrity: StartupAssetIntegrityService(
          flutterAssetsDirectory: assetsPath,
        ),
      );

      expect(runnerResult.result.isSuccess, isFalse);
      expect(runnerResult.missingApplicationFiles, [
        'Γραμματοσειρές/εικονίδια',
      ]);

      final message = runnerResult.result.message ?? '';
      expect(message, contains('Γραμματοσειρές/εικονίδια'));
      expect(
        message.indexOf('Γραμματοσειρές/εικονίδια'),
        lessThan(message.indexOf('2)')),
        reason: 'το δομικό εύρημα οφείλει να προηγείται του σφάλματος βάσης',
      );
    },
  );

  test('ελλιπή αρχεία με υγιή βάση → η εκκίνηση δεν εμποδίζεται', () async {
    final assetsPath = await _createFlutterAssets(tempRoot, withFonts: false);
    final dbPath = p.join(tempRoot.path, 'υγιής.db');
    await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
    await SettingsService().setDatabasePath(dbPath);

    final runnerResult = await runDatabaseInitChecks(
      assetIntegrity: StartupAssetIntegrityService(
        flutterAssetsDirectory: assetsPath,
      ),
    );

    expect(runnerResult.result.isSuccess, isTrue);
    expect(runnerResult.missingApplicationFiles, [
      'Γραμματοσειρές/εικονίδια',
    ]);
  });

  test('άρτια αρχεία → καμία αναφορά ελλείψεων', () async {
    final assetsPath = await _createFlutterAssets(tempRoot, withFonts: true);
    final dbPath = p.join(tempRoot.path, 'άρτια.db');
    await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
    await SettingsService().setDatabasePath(dbPath);

    final runnerResult = await runDatabaseInitChecks(
      assetIntegrity: StartupAssetIntegrityService(
        flutterAssetsDirectory: assetsPath,
      ),
    );

    expect(runnerResult.missingApplicationFiles, isEmpty);
  });
}
