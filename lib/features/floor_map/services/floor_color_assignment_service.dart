import 'dart:math';

import 'package:flutter/material.dart';

/// Υπηρεσία ανάθεσης χρωμάτων ανά όροφο (floor) για τμήματα χάρτη (π.χ. FloorSection).
///
/// Διατηρεί in-memory cache χρωμάτων που έχουν ήδη χρησιμοποιηθεί ανά `floorId`
/// ώστε κάθε νέα οντότητα να επιλέγει χρώμα μεγάλης διαφοροποίησης (contrast)
/// από τα υπάρχοντα. Η ενημέρωση μοντέλου γίνεται προαιρετικά μέσω [onColorOverride].
class FloorColorAssignmentService {
  FloorColorAssignmentService._();

  /// Προεπιλεγμένη μοναδική (singleton) εμφάνιση της υπηρεσίας.
  static final FloorColorAssignmentService instance =
      FloorColorAssignmentService._();

  factory FloorColorAssignmentService() => instance;

  final Map<int, Set<Color>> _usedColorsPerFloor = {};
  final Random _random = Random();
  static const List<double> _variantLightnessSteps = [0.16, -0.16, 0.28, -0.28];

  /// Καλείται όταν το μοντέλο είναι διαθέσιμο: ενημέρωση αποθηκευμένου χρώματος
  /// μετά από χειροκίνητη αντικατάσταση (override).
  void Function(int floorId, Color newColor)? onColorOverride;

  /// Ποιοτική παλέτα: χρώματα με ξεχωριστές αποχρώσεις (hue), υψηλή κορεσμότητα
  /// (saturation), χωρίς πολλαπλές αποχρώσεις του ίδιου «μπλε» κ.λπ.
  static const List<Color> qualitativePalette = [
    Color(0xFFE53935), // red
    Color(0xFF43A047), // green
    Color(0xFF1565C0), // blue
    Color(0xFFF57C00), // orange
    Color(0xFF6A1B9A), // purple
    Color(0xFFF9A825), // amber / deep yellow
    Color(0xFF5D4037), // brown
    Color(0xFFC2185B), // pink
    Color(0xFF00897B), // teal
    Color(0xFF4527A0), // deep violet
    Color(0xFFBF360C), // deep red / rust
    Color(0xFF546E7A), // blue-grey (μία «ψυχρή» γκριζογάλανη αποχρώση)
    Color(0xFF827717), // olive
    Color(0xFFD500F9), // vivid magenta
    Color(0xFF00ACC1), // cyan
    Color(0xFF33691E), // dark lime / forest
    Color(0xFFEF6C00), // dark orange
    Color(0xFFAD1457), // raspberry
    Color(0xFF00695C), // dark teal
    Color(0xFF7CB342), // apple / light green (διακριτό από το βασικό πράσινο)
    Color(0xFFFF6F00), // deep amber
    Color(0xFF37474F), // blue-grey dark
    Color(0xFFFFEA00), // pure yellow accent
    Color(0xFF880E4F), // burgundy
  ];

  /// Προεπισκόπηση του επόμενου χρώματος χωρίς ενημέρωση cache (για διάλογο επιβεβαίωσης).
  Color peekNextDistinctColor(
    int floorId, {
    Iterable<Color>? additionalUsed,
  }) {
    final cached = _usedColorsPerFloor[floorId] ?? <Color>{};
    final combined = <Color>{
      ...cached,
      ...?additionalUsed,
    };
    return _computeNextDistinctColor(combined);
  }

  /// Επόμενο χρώμα για τον όροφο: όταν δεν υπάρχουν ακόμα χρώματα στο σύνολο
  /// επιλέγεται ντετερμινιστικά η πρώτη απόχρωση της παλέτας (ώστε να ταιριάζει
  /// με [peekNextDistinctColor]). Αλλιώς μέγιστη ελάχιστη απόσταση RGB.
  ///
  /// Το [additionalUsed] χρησιμοποιείται για χρώματα που ήδη εμφανίζονται στο
  /// φύλλο από τη βάση αλλά δεν έχουν ακόμη γραφτεί στο in-memory cache.
  Color getNextDistinctColor(
    int floorId, {
    Iterable<Color>? additionalUsed,
  }) {
    final cached = _usedColorsPerFloor.putIfAbsent(floorId, () => <Color>{});
    final combined = <Color>{
      ...cached,
      ...?additionalUsed,
    };
    final chosen = _computeNextDistinctColor(combined);
    cached.add(chosen);
    return chosen;
  }

  Color _computeNextDistinctColor(Set<Color> combined) {
    final availableBase = qualitativePalette
        .where((c) => !_containsRgb(combined, c))
        .toList(growable: false);
    if (combined.isEmpty) {
      return qualitativePalette[0];
    }
    if (availableBase.isNotEmpty) {
      return _pickMaxMinRgbDistance(availableBase, combined);
    }
    final variants = _generateShadeVariants(combined);
    if (variants.isNotEmpty) {
      return _pickMaxMinRgbDistance(variants, combined);
    }
    return qualitativePalette[_random.nextInt(qualitativePalette.length)];
  }

  /// Ενημερώνει το cache: αφαιρεί προαιρετικά ένα παλιό χρώμα από το σύνολο
  /// χρήσης και προσθέτει το [newColor]. Καλεί [onColorOverride] αν έχει οριστεί.
  void overrideColor(
    int floorId,
    Color newColor, {
    Color? replaceUsed,
  }) {
    final used = _usedColorsPerFloor.putIfAbsent(floorId, () => <Color>{});
    if (replaceUsed != null) {
      used.remove(replaceUsed);
    }
    used.add(newColor);
    onColorOverride?.call(floorId, newColor);
  }

  void clearCacheForFloor(int floorId) {
    _usedColorsPerFloor.remove(floorId);
  }

  void clearAllCache() {
    _usedColorsPerFloor.clear();
  }

  /// Αφαιρεί συγκεκριμένο χρώμα από τον όροφο (RGB σύγκριση, αγνοεί alpha).
  void removeColorFromFloor(int floorId, Color color) {
    final used = _usedColorsPerFloor[floorId];
    if (used == null || used.isEmpty) return;
    used.removeWhere((c) => _sameRgb(c, color));
    if (used.isEmpty) {
      _usedColorsPerFloor.remove(floorId);
    }
  }

  /// Ανάγνωση cache χωρίς τροποποίηση (immutable view).
  Map<int, Set<Color>> get usedColorsPerFloor =>
      Map<int, Set<Color>>.unmodifiable({
        for (final e in _usedColorsPerFloor.entries)
          e.key: Set<Color>.unmodifiable(e.value),
      });

  Color _pickMaxMinRgbDistance(List<Color> candidates, Set<Color> used) {
    Color? best;
    var bestScore = -1.0;
    for (final candidate in candidates) {
      var minDist = double.infinity;
      for (final u in used) {
        final d = _rgbDistanceSquared(candidate, u);
        if (d < minDist) {
          minDist = d;
        }
      }
      if (minDist > bestScore) {
        bestScore = minDist;
        best = candidate;
      }
    }
    return best ?? qualitativePalette.first;
  }

  List<Color> _generateShadeVariants(Set<Color> used) {
    final out = <Color>[];
    for (final base in qualitativePalette) {
      final hsl = HSLColor.fromColor(base);
      for (final delta in _variantLightnessSteps) {
        final nextL = (hsl.lightness + delta).clamp(0.12, 0.88).toDouble();
        final variant = hsl.withLightness(nextL).toColor();
        if (_containsRgb(used, variant)) continue;
        if (_containsRgb(out.toSet(), variant)) continue;
        out.add(variant);
      }
    }
    return out;
  }

  static bool _containsRgb(Iterable<Color> colors, Color c) {
    for (final e in colors) {
      if (_sameRgb(e, c)) return true;
    }
    return false;
  }

  static bool _sameRgb(Color a, Color b) =>
      _channel255(a, 16) == _channel255(b, 16) &&
      _channel255(a, 8) == _channel255(b, 8) &&
      _channel255(a, 0) == _channel255(b, 0);

  static double _rgbDistanceSquared(Color a, Color b) {
    final ar = _channel255(a, 16);
    final ag = _channel255(a, 8);
    final ab = _channel255(a, 0);
    final br = _channel255(b, 16);
    final bg = _channel255(b, 8);
    final bb = _channel255(b, 0);
    final dr = ar - br;
    final dg = ag - bg;
    final db = ab - bb;
    return (dr * dr + dg * dg + db * db).toDouble();
  }

  static int _channel255(Color c, int shift) => (c.toARGB32() >> shift) & 0xFF;
}
