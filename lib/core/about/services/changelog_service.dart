import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/changelog_entry.dart';

/// Φόρτωση και ταξινόμηση του ιστορικού αλλαγών από το asset JSON.
class ChangelogService {
  ChangelogService({
    Future<String> Function(String assetPath)? loadAsset,
  }) : _loadAsset = loadAsset ?? ((path) => rootBundle.loadString(path));

  static const String _assetPath = 'assets/changelog.json';

  final Future<String> Function(String assetPath) _loadAsset;

  Future<List<ChangelogEntry>> load() async {
    try {
      final raw = await _loadAsset(_assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw FormatException(
          'Το changelog.json πρέπει να είναι λίστα εγγραφών.',
        );
      }
      final parsed = decoded
          .cast<dynamic>()
          .map(
            (e) =>
                ChangelogEntry.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .where((e) => e.version.isNotEmpty)
          .toList();

      ChangelogEntry? unreleased;
      final released = <ChangelogEntry>[];

      for (final entry in parsed) {
        if (entry.isUnreleased) {
          unreleased = entry;
        } else {
          released.add(entry);
        }
      }

      released.sort((a, b) => _compareVersionsDesc(a.version, b.version));

      if (unreleased != null && unreleased.hasContent) {
        return [unreleased, ...released];
      }
      return released;
    } catch (_) {
      return const <ChangelogEntry>[];
    }
  }

  /// Σύγκριση semver τύπου major.minor.patch (φθίνουσα σειρά).
  static int _compareVersionsDesc(String a, String b) {
    final pa = _parseParts(a);
    final pb = _parseParts(b);
    for (var i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return vb.compareTo(va);
    }
    return 0;
  }

  static List<int> _parseParts(String v) {
    final parts = v.split('.');
    final out = <int>[];
    for (final p in parts.take(3)) {
      final n = int.tryParse(p.trim());
      if (n != null) out.add(n);
    }
    while (out.length < 3) {
      out.add(0);
    }
    return out;
  }
}
