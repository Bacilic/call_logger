import 'dart:math' as math;

import '../database/database_helper.dart';
import '../database/dictionary_repository.dart';
import 'dictionary_service.dart';

/// Ελαφρύς ορθογραφικός έλεγχος: στατικό λεξικό (κλειδί→παραλλαγές) + προσωπικές λέξεις.
/// Χωρίς εξωτερικές βιβλιοθήκες· οι προτάσεις με Levenshtein σε κλειδιά (μέγ. απόσταση 2).
///
/// (Όνομα κλάσης: αποφυγή σύγκρουσης με [SpellCheckService] του Flutter SDK.)
class LexiconSpellCheckService {
  LexiconSpellCheckService();

  final Map<String, Set<String>> _variants = <String, Set<String>>{};
  final Map<String, String> _primaryDisplay = <String, String>{};
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Φόρτωση από χάρτη παραλλαγών (πυρήνας) + `user_dictionary`.
  Future<void> init({
    required Map<String, Set<String>> lexiconVariants,
  }) async {
    _variants
      ..clear()
      ..addAll({
        for (final e in lexiconVariants.entries)
          e.key: Set<String>.from(e.value),
      });
    _rebuildPrimaryDisplays();
    try {
      final db = await DatabaseHelper.instance.database;
      final user = await DictionaryRepository(db).getUserLexiconEntries();
      for (final entry in user) {
        _addVariant(entry.normalizedKey, entry.displayWord);
      }
    } catch (_) {}
    _initialized = true;
  }

  /// Προσθήκη στη βάση και στο in-memory χάρτη.
  Future<void> insertUserWord(String word) async {
    final k = DictionaryService.canonicalLexiconKey(word);
    if (k.length < 2) return;
    var display = word.trim().isEmpty ? k : word.trim();
    if (!DictionaryService.hasGreekTonos(display)) {
      final coreVariants = _variants[k];
      if (coreVariants != null && hasAnyGreekTonos(coreVariants)) {
        display = DictionaryService.primaryDisplayForVariants(k, coreVariants);
      }
    }
    _addVariant(k, display);
    try {
      final db = await DatabaseHelper.instance.database;
      await DictionaryRepository(db).insertUserWord(display);
    } catch (_) {}
  }

  /// Συμβατότητα με παλιό όνομα.
  Future<void> addUserWord(String word) => insertUserWord(word);

  bool isCorrect(String word) {
    final key = DictionaryService.canonicalLexiconKey(word);
    if (key.length < 2) return true;
    if (_shouldSkipToken(key)) return true;
    final variants = _variants[key];
    if (variants == null || variants.isEmpty) return false;

    final input = word.trim();
    // Μόνο άτονες παραλλαγές στο λεξικό → δέχεται οποιαδήποτε επιφάνεια για το κλειδί.
    if (!hasAnyGreekTonos(variants)) return true;

    // Υπάρχει τουλάχιστον μία τονισμένη παραλλαγή → απαιτείται ακριβής ταύτιση.
    final inputLower = input.toLowerCase();
    for (final variant in variants) {
      if (variant.trim().toLowerCase() == inputLower) return true;
    }
    return false;
  }

  /// Έως 5 προτάσεις (κύρια μορφή εμφάνισης) με Levenshtein ≤ 2 στα κλειδιά.
  List<String> getSuggestions(String wrongWord) {
    final key = DictionaryService.canonicalLexiconKey(wrongWord);
    if (key.length < 2) return [];
    final keyRunes = key.runes.toList();
    final scored = <_Suggestion>[];
    for (final entry in _variants.entries) {
      final candKey = entry.key;
      if ((candKey.runes.length - keyRunes.length).abs() > 2) continue;
      final d = _levenshteinBounded(keyRunes, candKey.runes.toList(), 2);
      if (d <= 2) {
        final display = _primaryDisplay[candKey] ?? entry.value.first;
        scored.add(_Suggestion(display, d, candKey));
      }
    }
    scored.sort((a, b) {
      final c = a.distance.compareTo(b.distance);
      if (c != 0) return c;
      if (a.display.toLowerCase() == wrongWord.toLowerCase() &&
          b.display.toLowerCase() != wrongWord.toLowerCase()) {
        return -1;
      }
      if (b.display.toLowerCase() == wrongWord.toLowerCase() &&
          a.display.toLowerCase() != wrongWord.toLowerCase()) {
        return 1;
      }
      return a.display.compareTo(b.display);
    });
    final out = <String>[];
    final seen = <String>{};
    for (final e in scored) {
      if (seen.add(e.display)) out.add(e.display);
      if (out.length >= 5) break;
    }
    return out;
  }

  void _addVariant(String key, String display) {
    final trimmed = display.trim();
    if (trimmed.isEmpty) return;
    final set = _variants.putIfAbsent(key, () => <String>{});
    set.add(trimmed);
    final current = _primaryDisplay[key];
    if (current == null ||
        DictionaryService.preferLexiconDisplay(trimmed, current)) {
      _primaryDisplay[key] = trimmed;
    }
  }

  void _rebuildPrimaryDisplays() {
    _primaryDisplay
      ..clear()
      ..addAll({
        for (final e in _variants.entries)
          e.key: DictionaryService.primaryDisplayForVariants(e.key, e.value),
      });
  }

  static bool hasAnyGreekTonos(Set<String> variants) {
    for (final v in variants) {
      if (DictionaryService.hasGreekTonos(v)) return true;
    }
    return false;
  }

  static bool _shouldSkipToken(String normalizedKey) {
    if (normalizedKey.isEmpty) return true;
    var hasLetter = false;
    for (final r in normalizedKey.runes) {
      final isGreek = r >= 0x0370 && r <= 0x03ff;
      final isLatin = (r >= 0x41 && r <= 0x5a) || (r >= 0x61 && r <= 0x7a);
      if (isGreek || isLatin) {
        hasLetter = true;
        break;
      }
    }
    return !hasLetter;
  }
}

class _Suggestion {
  _Suggestion(this.display, this.distance, this.key);

  final String display;
  final int distance;
  final String key;
}

/// Levenshtein σε λίστες rune· επιστρέφει > maxDist αν η ελάχιστη απόσταση υπερβαίνει το όριο.
int _levenshteinBounded(List<int> s, List<int> t, int maxDist) {
  if (s.isEmpty) return t.length <= maxDist ? t.length : maxDist + 1;
  if (t.isEmpty) return s.length <= maxDist ? s.length : maxDist + 1;
  if ((s.length - t.length).abs() > maxDist) return maxDist + 1;

  final m = s.length;
  final n = t.length;
  var previous = List<int>.generate(m + 1, (i) => i);
  for (var j = 1; j <= n; j++) {
    var rowMin = j;
    final current = List<int>.filled(m + 1, 0);
    current[0] = j;
    for (var i = 1; i <= m; i++) {
      final cost = s[i - 1] == t[j - 1] ? 0 : 1;
      current[i] = math.min(
        math.min(current[i - 1] + 1, previous[i] + 1),
        previous[i - 1] + cost,
      );
      if (current[i] < rowMin) rowMin = current[i];
    }
    if (rowMin > maxDist) return maxDist + 1;
    previous = current;
  }
  return previous[m];
}
