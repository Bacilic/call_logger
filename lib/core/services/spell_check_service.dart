import 'dart:math' as math;

import '../database/database_helper.dart';
import 'dictionary_service.dart';

/// Ελαφρύς ορθογραφικός έλεγχος: στατικό λεξικό (strip→εμφάνιση) + προσωπικές λέξεις.
/// Χωρίς εξωτερικές βιβλιοθήκες· οι προτάσεις με Levenshtein σε κλειδιά (μέγ. απόσταση 2).
///
/// (Όνομα κλάσης: αποφυγή σύγκρουσης με [SpellCheckService] του Flutter SDK.)
class LexiconSpellCheckService {
  LexiconSpellCheckService();

  /// Κλειδί χαμηλής μορφής → μορφή εμφάνισης (με τόνους όταν υπάρχουν στο map).
  final Map<String, String> _lexicon = <String, String>{};
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Φόρτωση από χάρτη που χτίστηκε από asset + `user_dictionary`.
  Future<void> init({required Map<String, String> lexiconMap}) async {
    _lexicon
      ..clear()
      ..addAll(lexiconMap);
    try {
      final user = await DatabaseHelper.instance.getUserWords();
      for (final w in user) {
        final k = DictionaryService.canonicalLexiconKey(w);
        if (k.length < 2) continue;
        if (!_lexicon.containsKey(k)) {
          _lexicon[k] = w;
        }
      }
    } catch (_) {}
    _initialized = true;
  }

  /// Προσθήκη στη βάση και στο in-memory χάρτι.
  Future<void> insertUserWord(String word) async {
    final k = DictionaryService.canonicalLexiconKey(word);
    if (k.length < 2) return;
    _lexicon[k] = word.trim().isEmpty ? k : word.trim();
    try {
      await DatabaseHelper.instance.insertUserWord(word);
    } catch (_) {}
  }

  /// Συμβατότητα με παλιό όνομα.
  Future<void> addUserWord(String word) => insertUserWord(word);

  bool isCorrect(String word) {
    final key = DictionaryService.canonicalLexiconKey(word);
    if (key.length < 2) return true;
    if (_shouldSkipToken(key)) return true;
    return _lexicon.containsKey(key);
  }

  /// Έως 5 προτάσεις (μορφή εμφάνισης με τόνους) με απόσταση Levenshtein ≤ 2 στα κλειδιά.
  List<String> getSuggestions(String wrongWord) {
    final key = DictionaryService.canonicalLexiconKey(wrongWord);
    if (key.length < 2) return [];
    final keyRunes = key.runes.toList();
    final scored = <_Suggestion>[];
    for (final entry in _lexicon.entries) {
      final candKey = entry.key;
      if ((candKey.runes.length - keyRunes.length).abs() > 2) continue;
      final d = _levenshteinBounded(keyRunes, candKey.runes.toList(), 2);
      if (d <= 2) {
        scored.add(_Suggestion(entry.value, d, candKey));
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
