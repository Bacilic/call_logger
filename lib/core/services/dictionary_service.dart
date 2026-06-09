import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Φόρτωση λεξικού-πυρήνας από αρχείο `.txt` στο δίσκο.
///
/// Εσωτερικά: κανονικοποιημένο κλειδί → σύνολο επιφανειακών μορφών (π.χ. «αίτημα», «αίτημά»).
class DictionaryService {
  DictionaryService();

  factory DictionaryService.empty() {
    final s = DictionaryService();
    s._loaded = true;
    return s;
  }

  final Map<String, Set<String>> _stripKeyToVariants = <String, Set<String>>{};
  bool _loaded = false;
  String? _loadedFromPath;

  bool get isLoaded => _loaded;

  int get wordCount => _stripKeyToVariants.length;

  /// Αφαιρεί μόνο ελληνικούς τόνους/διαλυτικά· διατηρεί υπόλοιπους χαρακτήρες και πεζά/κεφαλαία.
  static String stripDiacritics(String input) {
    return input
        .replaceAll('ΐ', 'ι')
        .replaceAll('ΰ', 'υ')
        .replaceAll('ά', 'α')
        .replaceAll('έ', 'ε')
        .replaceAll('ή', 'η')
        .replaceAll('ί', 'ι')
        .replaceAll('ϊ', 'ι')
        .replaceAll('ό', 'ο')
        .replaceAll('ύ', 'υ')
        .replaceAll('ϋ', 'υ')
        .replaceAll('ώ', 'ω')
        .replaceAll('Ά', 'Α')
        .replaceAll('Έ', 'Ε')
        .replaceAll('Ή', 'Η')
        .replaceAll('Ί', 'Ι')
        .replaceAll('Ϊ', 'Ι')
        .replaceAll('Ό', 'Ο')
        .replaceAll('Ύ', 'Υ')
        .replaceAll('Ϋ', 'Υ')
        .replaceAll('Ώ', 'Ω');
  }

  /// Κλειδί αναζήτησης στο λεξικό ορθογραφίας.
  static String canonicalLexiconKey(String input) =>
      stripDiacritics(input.trim()).toLowerCase();

  /// Κύρια μορφή εμφάνισης ανά κλειδί (για προτάσεις / legacy API).
  Map<String, String> get stripKeyToDisplayMap {
    return UnmodifiableMapView({
      for (final e in _stripKeyToVariants.entries)
        e.key: primaryDisplayForVariants(e.key, e.value),
    });
  }

  /// Όλες οι καταχωρημένες επιφανειακές μορφές ανά κλειδί.
  Map<String, Set<String>> get stripKeyToVariantsMap =>
      UnmodifiableMapView({
        for (final e in _stripKeyToVariants.entries)
          e.key: UnmodifiableSetView(Set<String>.from(e.value)),
      });

  /// Επιλογή κύριας μορφής από σύνολο παραλλαγών.
  static String primaryDisplayForVariants(String key, Set<String> variants) {
    if (variants.isEmpty) return key;
    var best = variants.first;
    for (final candidate in variants) {
      if (preferLexiconDisplay(candidate, best)) {
        best = candidate;
      }
    }
    return best;
  }

  /// Φόρτωση από αρχείο TXT στο δίσκο (μόνο πηγή — χωρίς asset fallback).
  Future<void> loadFromFile(String filePath) async {
    final norm = filePath.trim();
    if (_loaded && _loadedFromPath == norm) return;
    _stripKeyToVariants.clear();
    final text = await File(norm).readAsString(encoding: utf8);
    _ingestText(text);
    _loaded = true;
    _loadedFromPath = norm;
  }

  void _ingestText(String text) {
    for (final line in const LineSplitter().convert(text)) {
      final display = line.trim();
      if (display.isEmpty || display.startsWith('#')) continue;
      final key = canonicalLexiconKey(display);
      if (key.length < 2) continue;
      _stripKeyToVariants.putIfAbsent(key, () => <String>{}).add(display);
    }
  }

  /// Προτιμάται ως εμφάνιση η μορφή με τόνους / μακρύτερη / λεξικογραφικά πρώτη.
  static bool preferLexiconDisplay(String candidate, String existing) {
    final cTon = hasGreekTonos(candidate);
    final eTon = hasGreekTonos(existing);
    if (cTon != eTon) return cTon;
    if (candidate.length != existing.length) {
      return candidate.length > existing.length;
    }
    return candidate.compareTo(existing) < 0;
  }

  static bool hasGreekTonos(String s) {
    const ton = 'άέήίόύώϊΐϋΰΆΈΉΊΌΎΏ';
    for (var i = 0; i < s.length; i++) {
      if (ton.contains(s[i])) return true;
    }
    return false;
  }

  bool isKnownWord(String token) {
    final key = canonicalLexiconKey(token);
    if (key.length < 2) return false;
    return _stripKeyToVariants.containsKey(key);
  }
}
