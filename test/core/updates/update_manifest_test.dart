import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateManifest.fromJson', () {
    test('parses valid manifest', () {
      final m = UpdateManifest.fromJson({
        'version': '0.24.0',
        'build': 32,
        'released': '2026-07-19',
        'zipFile': 'call_logger_0.24.0.zip',
        'sha256': 'abc123',
      });

      expect(m, isNotNull);
      expect(m!.version, '0.24.0');
      expect(m.build, 32);
      expect(m.released, '2026-07-19');
      expect(m.zipFile, 'call_logger_0.24.0.zip');
      expect(m.sha256, 'abc123');
    });

    test('returns null for broken or incomplete JSON', () {
      expect(UpdateManifest.fromJson(null), isNull);
      expect(UpdateManifest.fromJson(<String, dynamic>{}), isNull);
      expect(
        UpdateManifest.fromJson({'version': '0.24.0'}),
        isNull,
      );
      expect(
        UpdateManifest.fromJson({
          'version': '',
          'build': 1,
          'released': '2026-01-01',
          'zipFile': 'a.zip',
          'sha256': 'x',
        }),
        isNull,
      );
      expect(
        UpdateManifest.fromJson({
          'version': '0.24.0',
          'build': 'not-a-number',
          'released': '2026-01-01',
          'zipFile': 'a.zip',
          'sha256': 'x',
        }),
        isNull,
      );
    });
  });

  group('UpdateManifest.compareVersions', () {
    test('0.23.1+31 is older than 0.24.0+32', () {
      expect(
        UpdateManifest.compareVersions(
          versionA: '0.23.1',
          buildA: 31,
          versionB: '0.24.0',
          buildB: 32,
        ),
        lessThan(0),
      );
      expect(
        UpdateManifest.compareVersions(
          versionA: '0.24.0',
          buildA: 32,
          versionB: '0.23.1',
          buildB: 31,
        ),
        greaterThan(0),
      );
    });

    test('same version with different build uses build as tie-breaker', () {
      expect(
        UpdateManifest.compareVersions(
          versionA: '0.23.1',
          buildA: 31,
          versionB: '0.23.1',
          buildB: 32,
        ),
        lessThan(0),
      );
      expect(
        UpdateManifest.compareVersions(
          versionA: '0.23.1',
          buildA: 32,
          versionB: '0.23.1',
          buildB: 31,
        ),
        greaterThan(0),
      );
      expect(
        UpdateManifest.compareVersions(
          versionA: '0.23.1',
          buildA: 31,
          versionB: '0.23.1',
          buildB: 31,
        ),
        0,
      );
    });

    test('compares numerically not as text (e.g. 0.9.0 < 0.10.0)', () {
      expect(
        UpdateManifest.compareVersions(
          versionA: '0.9.0',
          buildA: 1,
          versionB: '0.10.0',
          buildB: 1,
        ),
        lessThan(0),
      );
    });
  });
}
