import 'package:call_logger/core/utils/lexicon_word_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LexiconWordMetrics', () {
    test('golden: δάσκαλος / δάσκαλός / μαϊμού / γάϊδαρό / ταΐζω', () {
      final daskalos = LexiconWordMetrics.compute('δάσκαλος');
      expect(daskalos.lettersCount, 8);
      expect(daskalos.diacriticMarkCount, 1);

      final daskalos2 = LexiconWordMetrics.compute('δάσκαλός');
      expect(daskalos2.lettersCount, 8);
      expect(daskalos2.diacriticMarkCount, 2);

      final maimou = LexiconWordMetrics.compute('μαϊμού');
      expect(maimou.lettersCount, 6);
      expect(maimou.diacriticMarkCount, 2);

      final gaidaro = LexiconWordMetrics.compute('γάϊδαρό');
      expect(gaidaro.lettersCount, 7);
      expect(gaidaro.diacriticMarkCount, 3);

      final taizo = LexiconWordMetrics.compute('ταΐζω');
      expect(taizo.lettersCount, 5);
      expect(taizo.diacriticMarkCount, 1);
    });

    test('hyphen and apostrophe count as diacritic marks only', () {
      final m = LexiconWordMetrics.compute('μάνα-κουκου');
      expect(m.lettersCount, 10);
      expect(m.diacriticMarkCount, 2);
    });

    test('empty and trim', () {
      expect(
        LexiconWordMetrics.compute('  ').lettersCount,
        0,
      );
    });
  });
}
