import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';

/// Φόρτωση συμπαγούς ελληνικού λεξικού από asset.
///
/// Εσωτερικά: `Map` από κανονικοποιημένο κλειδί (χωρίς τόνους, πεζά) σε μορφή
/// εμφάνισης (π.χ. με τόνους όταν υπάρχουν στο corpus).
class DictionaryService {
  DictionaryService({String? assetPath})
      : assetPath = assetPath ?? AppConfig.greekDictionaryAsset;

  final String assetPath;
  final Map<String, String> _stripKeyToDisplay = <String, String>{};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  int get wordCount => _stripKeyToDisplay.length;

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

  /// Αμετάβλητο αντίγραφο για [LexiconSpellCheckService].
  Map<String, String> get stripKeyToDisplayMap =>
      UnmodifiableMapView(_stripKeyToDisplay);

  Future<void> load() async {
    if (_loaded) return;
    final sw = Stopwatch()..start();
    final text = await rootBundle.loadString(assetPath);
    final lines = const LineSplitter().convert(text);
    for (final line in lines) {
      final display = line.trim();
      if (display.isEmpty || display.startsWith('#')) continue;
      final key = canonicalLexiconKey(display);
      if (key.length < 2) continue;
      final existing = _stripKeyToDisplay[key];
      if (existing == null || _preferDisplay(display, existing)) {
        _stripKeyToDisplay[key] = display;
      }
    }
    _loaded = true;
    sw.stop();
    assert(() {
      debugPrint(
        'DictionaryService: wordCount=$wordCount loadMs=${sw.elapsedMilliseconds}',
      );
      return true;
    }());
  }

  /// Προτιμάται ως εμφάνιση η μορφή με τόνους / μακρύτερη / λεξικογραφικά πρώτη.
  static bool _preferDisplay(String candidate, String existing) {
    final cTon = _hasGreekTonos(candidate);
    final eTon = _hasGreekTonos(existing);
    if (cTon != eTon) return cTon;
    if (candidate.length != existing.length) {
      return candidate.length > existing.length;
    }
    return candidate.compareTo(existing) < 0;
  }

  static bool _hasGreekTonos(String s) {
    const ton = 'άέήίόύώϊΐϋΰΆΈΉΊΌΎΏ';
    for (var i = 0; i < s.length; i++) {
      if (ton.contains(s[i])) return true;
    }
    return false;
  }

  bool isKnownWord(String token) {
    final key = canonicalLexiconKey(token);
    if (key.length < 2) return false;
    return _stripKeyToDisplay.containsKey(key);
  }
}
