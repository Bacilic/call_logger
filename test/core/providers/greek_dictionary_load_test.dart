import 'dart:io';

import 'package:call_logger/core/services/dictionary_service.dart';
import 'package:call_logger/core/utils/bundled_dictionary_assets.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('DictionaryService.stripDiacritics removes Greek tonos only', () {
    expect(
      DictionaryService.stripDiacritics('Άλφα'),
      'Αλφα',
    );
    expect(
      DictionaryService.stripDiacritics('άέήίόύώ'),
      'αεηιουω',
    );
  });

  test('normalizeDictionaryForm keeps underscores, strips accents', () {
    expect(
      SearchTextNormalizer.normalizeDictionaryForm('Καλή_μέρα'),
      'καλη_μερα',
    );
    expect(
      SearchTextNormalizer.normalizeDictionaryForm('ΕΠΙΛΥΣΗ'),
      'επιλυση',
    );
  });

  test('DictionaryService loads bundled txt and resolves known words', () async {
    String text;
    final assets = await listBundledDictionaryAssets();
    if (assets.isNotEmpty) {
      final asset = assets.firstWhere(
        (a) => a.contains('greek_core'),
        orElse: () => assets.first,
      );
      text = await rootBundle.loadString(asset);
    } else {
      final projectFile = File('assets/dictionaries/greek_core_60k.txt');
      expect(
        await projectFile.exists(),
        isTrue,
        reason:
            'Απαιτείται greek_core_60k.txt στο assets/dictionaries/ ή στο manifest',
      );
      text = await projectFile.readAsString();
    }
    final dir = await Directory.systemTemp.createTemp('dict_load_test_');
    final file = File('${dir.path}/lexicon.txt');
    await file.writeAsString(text);
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final s = DictionaryService();
    final sw = Stopwatch()..start();
    await s.loadFromFile(file.path);
    sw.stop();

    expect(s.wordCount, inInclusiveRange(25000, 80000));
    expect(sw.elapsedMilliseconds, lessThan(5000));

    expect(s.isKnownWord('επίλυση'), isTrue);
    expect(s.isKnownWord('επιλυση'), isTrue);
    expect(s.isKnownWord('xxxxxxxxxxnotaword'), isFalse);
  });
}
