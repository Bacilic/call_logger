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
        'improvements': ['Μικροβελτίωση'],
        'changed': ['Αλλαγή'],
        'fixed': ['Διόρθωση'],
      });

      expect(entry.version, '1.2.3');
      expect(entry.date, '2026-06-27');
      expect(entry.added, ['Νέο feature']);
      expect(entry.improvements, ['Μικροβελτίωση']);
      expect(entry.changed, ['Αλλαγή']);
      expect(entry.fixed, ['Διόρθωση']);
    });

    test('treats missing category arrays as empty', () {
      final entry = ChangelogEntry.fromJson({
        'version': '0.1.0',
        'date': '',
      });

      expect(entry.added, isEmpty);
      expect(entry.improvements, isEmpty);
      expect(entry.changed, isEmpty);
      expect(entry.fixed, isEmpty);
      expect(entry.hasContent, isFalse);
    });

    test('hasContent is true when any category has items', () {
      final entry = ChangelogEntry.fromJson({
        'version': 'Unreleased',
        'date': '',
        'fixed': ['Διόρθωση'],
      });

      expect(entry.isUnreleased, isTrue);
      expect(entry.hasContent, isTrue);
    });

    test('parses improvements and hasContent when only improvements', () {
      final entry = ChangelogEntry.fromJson({
        'version': 'Unreleased',
        'date': '',
        'improvements': ['Μικρή βελτίωση UI'],
      });

      expect(entry.improvements, ['Μικρή βελτίωση UI']);
      expect(entry.added, isEmpty);
      expect(entry.changed, isEmpty);
      expect(entry.fixed, isEmpty);
      expect(entry.hasContent, isTrue);
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
      final latestReleased = entries.firstWhere(
        (e) => !e.isUnreleased,
        orElse: () => throw StateError('No released version in changelog'),
      );
      expect(latestReleased.version, pubVersion);
    });

    test('unreleased entry is first when it has content', () async {
      final entries = await ChangelogService().load();
      final unreleased = entries.where((e) => e.isUnreleased).toList();

      if (unreleased.isEmpty) {
        return;
      }

      expect(unreleased.single.hasContent, isTrue);
      expect(entries.first.isUnreleased, isTrue);
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
