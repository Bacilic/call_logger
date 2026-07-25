import 'dart:io';

import 'package:call_logger/core/services/startup_asset_integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'startup_asset_integrity_',
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<void> createAllCriticalAssets(Directory flutterAssets) async {
    await flutterAssets.create(recursive: true);
    await Directory(p.join(flutterAssets.path, 'fonts')).create();
    await File(p.join(flutterAssets.path, 'FontManifest.json')).writeAsString(
      '[]',
    );
    await File(p.join(flutterAssets.path, 'AssetManifest.bin')).writeAsBytes(
      const <int>[],
    );
    await Directory(p.join(flutterAssets.path, 'assets')).create();
    final cupertino = File(
      p.join(
        flutterAssets.path,
        'packages',
        'cupertino_icons',
        'assets',
        'CupertinoIcons.ttf',
      ),
    );
    await cupertino.parent.create(recursive: true);
    await cupertino.writeAsBytes(const <int>[0]);
  }

  group('StartupAssetIntegrityService.findMissingCriticalAssets', () {
    test('Περίπτωση Α: όλα παρόντα → κενή λίστα', () async {
      final flutterAssets = Directory(p.join(tempRoot.path, 'flutter_assets'));
      await createAllCriticalAssets(flutterAssets);

      final missing = StartupAssetIntegrityService(
        flutterAssetsDirectory: flutterAssets.path,
      ).findMissingCriticalAssets();

      expect(missing, isEmpty);
    });

    test(
      'Περίπτωση Β: λείπουν fonts και AssetManifest.bin → μόνο αυτές οι ετικέτες',
      () async {
        final flutterAssets = Directory(
          p.join(tempRoot.path, 'flutter_assets'),
        );
        await createAllCriticalAssets(flutterAssets);
        await Directory(p.join(flutterAssets.path, 'fonts')).delete(
          recursive: true,
        );
        await File(p.join(flutterAssets.path, 'AssetManifest.bin')).delete();

        final missing = StartupAssetIntegrityService(
          flutterAssetsDirectory: flutterAssets.path,
        ).findMissingCriticalAssets();

        expect(missing, hasLength(2));
        expect(missing, contains('Γραμματοσειρές/εικονίδια'));
        expect(missing, contains('Κατάλογος πόρων'));
        expect(missing, isNot(contains('Κατάλογος γραμματοσειρών')));
        expect(missing, isNot(contains('Εικόνες εφαρμογής')));
        expect(missing, isNot(contains('Εικονίδια Cupertino')));
      },
    );

    test(
      'Περίπτωση Γ: λείπει ολόκληρος ο φάκελος flutter_assets → μη κενή λίστα',
      () {
        final missingPath = p.join(tempRoot.path, 'missing_flutter_assets');

        final missing = StartupAssetIntegrityService(
          flutterAssetsDirectory: missingPath,
        ).findMissingCriticalAssets();

        expect(missing, isNotEmpty);
        expect(missing, contains('Γραμματοσειρές/εικονίδια'));
        expect(missing, contains('Κατάλογος γραμματοσειρών'));
        expect(missing, contains('Κατάλογος πόρων'));
        expect(missing, contains('Εικόνες εφαρμογής'));
        expect(missing, contains('Εικονίδια Cupertino'));
      },
    );
  });
}
