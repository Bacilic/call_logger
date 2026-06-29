import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/about/models/changelog_entry.dart';
import 'package:call_logger/core/about/services/changelog_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChangelogEntry.fromJson', () {
    test('maps version, date and category lists', () {
      final entry = ChangelogEntry.fromJson({
        'version': '1.2.3',
        'date': '2026-06-27',
        'added': ['Νέο feature'],
        'changed': ['Αλλαγή'],
        'fixed': ['Διόρθωση'],
      });

      expect(entry.version, '1.2.3');
      expect(entry.date, '2026-06-27');
      expect(entry.added, ['Νέο feature']);
      expect(entry.changed, ['Αλλαγή']);
      expect(entry.fixed, ['Διόρθωση']);
    });

    test('treats missing category arrays as empty', () {
      final entry = ChangelogEntry.fromJson({
        'version': '0.1.0',
        'date': '',
      });

      expect(entry.added, isEmpty);
      expect(entry.changed, isEmpty);
      expect(entry.fixed, isEmpty);
    });
  });

  group('ChangelogService', () {
    test('assets/changelog.json is valid JSON array', () async {
      final raw = await rootBundle.loadString('assets/changelog.json');
      expect(
        () => jsonDecode(raw),
        returnsNormally,
        reason: 'Το assets/changelog.json πρέπει να είναι έγκυρο JSON',
      );
      expect(jsonDecode(raw), isA<List>());
    });

    test('load parses bundled changelog without errors', () async {
      final entries = await ChangelogService().load();

      expect(entries, isNotEmpty);
      expect(entries.every((e) => e.version.isNotEmpty), isTrue);
    });

    test('latest released version matches pubspec NAME', () async {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(r'^version:\s*([\d.]+)\+', multiLine: true)
          .firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml version line');
      final pubVersion = match!.group(1)!;

      final entries = await ChangelogService().load();
      expect(entries.first.version, pubVersion);
    });

    test('load sorts semver versions descending', () async {
      final entries = await ChangelogService().load();
      final numericVersions = entries
          .where((e) => RegExp(r'^\d+\.\d+\.\d+').hasMatch(e.version))
          .map((e) => e.version)
          .toList();

      expect(numericVersions, isNotEmpty);

      for (var i = 0; i < numericVersions.length - 1; i++) {
        final a = numericVersions[i].split('.').map(int.parse).toList();
        final b = numericVersions[i + 1].split('.').map(int.parse).toList();
        final cmp = _compareSemverDesc(a, b);
        expect(
          cmp,
          lessThanOrEqualTo(0),
          reason:
              '${numericVersions[i]} should sort before ${numericVersions[i + 1]}',
        );
      }
    });
  });
}

int _compareSemverDesc(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    final va = i < a.length ? a[i] : 0;
    final vb = i < b.length ? b[i] : 0;
    if (va != vb) return vb.compareTo(va);
  }
  return 0;
}
