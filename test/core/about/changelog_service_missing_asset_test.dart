import 'package:call_logger/core/about/services/changelog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChangelogService.load — missing/corrupt asset', () {
    test('loader που πετάει → κενή λίστα χωρίς εξαίρεση', () async {
      final service = ChangelogService(
        loadAsset: (_) async {
          throw Exception('Unable to load asset: assets/changelog.json');
        },
      );

      final entries = await service.load();

      expect(entries, isEmpty);
      expect(entries, equals(const []));
    });

    test('έγκυρο JSON → κανονικές εγγραφές', () async {
      const json = '''
[
  {
    "version": "1.0.0",
    "date": "2026-01-01",
    "added": ["Δοκιμαστική εγγραφή"],
    "improvements": [],
    "changed": [],
    "fixed": []
  }
]
''';
      final service = ChangelogService(
        loadAsset: (_) async => json,
      );

      final entries = await service.load();

      expect(entries, hasLength(1));
      expect(entries.single.version, '1.0.0');
      expect(entries.single.added, ['Δοκιμαστική εγγραφή']);
    });
  });
}
