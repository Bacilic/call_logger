import 'package:call_logger/core/services/dictionary_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('DictionaryService loads asset and resolves known words', () async {
    final s = DictionaryService();
    final sw = Stopwatch()..start();
    await s.load();
    sw.stop();

    expect(s.wordCount, inInclusiveRange(62000, 70000));
    // Στόχος πλάνου (~80 ms) — σε flutter test / VM ο χρόνος μεταβάλλεται.
    expect(sw.elapsedMilliseconds, lessThan(5000));

    expect(s.isKnownWord('επίλυση'), isTrue);
    expect(s.isKnownWord('επιλυση'), isTrue);
    expect(s.isKnownWord('xxxxxxxxxxnotaword'), isFalse);
  });
}
