// Δομικός έλεγχος αρχείων πριν από τους ελέγχους βάσης.
//
// Συμβόλαιο: κάθε δομικός έλεγχος αρχείων της εφαρμογής προηγείται κάθε ελέγχου
// βάσης· μοιραία έλλειψη τερματίζει τη διάγνωση, μη μοιραία δεν την τερματίζει
// αλλά προηγείται στην αναφορά.
//
//   flutter test test/core/init/startup_structural_check_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/init/startup_structural_check.dart';
import 'package:call_logger/core/services/startup_asset_integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<Directory> _createFlutterAssets(
  Directory root, {
  bool withFonts = true,
  bool withImages = true,
}) async {
  final assets = Directory(p.join(root.path, 'flutter_assets'));
  await assets.create(recursive: true);
  if (withFonts) {
    await Directory(p.join(assets.path, 'fonts')).create(recursive: true);
  }
  if (withImages) {
    await Directory(p.join(assets.path, 'assets')).create(recursive: true);
  }
  await File(p.join(assets.path, 'FontManifest.json')).writeAsString('[]');
  await File(p.join(assets.path, 'AssetManifest.bin')).writeAsBytes(const [0]);
  final cupertino = File(
    p.join(assets.path, 'packages', 'cupertino_icons', 'assets', 'CupertinoIcons.ttf'),
  );
  await cupertino.parent.create(recursive: true);
  await cupertino.writeAsBytes(const [0]);
  return assets;
}

DatabaseInitResult _databaseFailure() => DatabaseInitResult.fileNotFound(
  r'C:\δεν\υπάρχει.db',
);

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('structural_check_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('detectMissingApplicationFiles', () {
    test('όλα στη θέση τους → τίποτα να αναφερθεί', () async {
      final assets = await _createFlutterAssets(tempRoot);

      final missing = detectMissingApplicationFiles(
        StartupAssetIntegrityService(flutterAssetsDirectory: assets.path),
      );

      expect(missing, isEmpty);
    });

    test('μερική ζημιά → αναφέρονται μόνο όσα λείπουν', () async {
      final assets = await _createFlutterAssets(tempRoot, withFonts: false);

      final missing = detectMissingApplicationFiles(
        StartupAssetIntegrityService(flutterAssetsDirectory: assets.path),
      );

      expect(missing, ['Γραμματοσειρές/εικονίδια']);
    });

    test('χωρίς ρίζα flutter_assets → σιωπή, δεν τρέχουμε από εγκατάσταση', () {
      // Σε πραγματική εγκατάσταση αυτή η κατάσταση δεν φτάνει ποτέ στη Dart:
      // ο έλεγχος πριν τη μηχανή Flutter τερματίζει την εφαρμογή.
      final missing = detectMissingApplicationFiles(
        StartupAssetIntegrityService(
          flutterAssetsDirectory: p.join(tempRoot.path, 'δεν_υπάρχει'),
        ),
      );

      expect(missing, isEmpty);
    });
  });

  group('withMissingApplicationFilesFirst', () {
    test('χωρίς ελλείψεις → το αποτέλεσμα μένει ανέπαφο', () {
      final base = _databaseFailure();

      final ranked = withMissingApplicationFilesFirst(base, const []);

      expect(ranked.message, base.message);
    });

    test('επιτυχής βάση → δεν μπλοκάρει, το μήνυμα μένει ανέπαφο', () {
      final base = DatabaseInitResult.success(r'C:\βάση.db');

      final ranked = withMissingApplicationFilesFirst(base, const [
        'Γραμματοσειρές/εικονίδια',
      ]);

      expect(ranked.message, base.message);
      expect(ranked.isSuccess, isTrue);
    });

    test('αποτυχία βάσης + ελλείψεις → τα αρχεία προηγούνται, η βάση δεύτερη', () {
      final base = _databaseFailure();

      final ranked = withMissingApplicationFilesFirst(base, const [
        'Γραμματοσειρές/εικονίδια',
        'Εικόνες εφαρμογής',
      ]);

      final message = ranked.message ?? '';
      final fileLine = message.indexOf('Γραμματοσειρές/εικονίδια');
      final databaseLine = message.indexOf(base.message ?? '');

      expect(fileLine, greaterThanOrEqualTo(0));
      expect(databaseLine, greaterThan(fileLine));
      expect(message, contains('Εικόνες εφαρμογής'));
      expect(message, contains('επανεγκατάσταση'));
    });

    test('η κατηγορία και οι ενέργειες ανάκτησης της βάσης δεν αλλοιώνονται', () {
      final base = _databaseFailure();

      final ranked = withMissingApplicationFilesFirst(base, const [
        'Εικόνες εφαρμογής',
      ]);

      expect(ranked.status, base.status);
      expect(ranked.recoveryKind, base.recoveryKind);
      expect(ranked.path, base.path);
    });
  });
}
