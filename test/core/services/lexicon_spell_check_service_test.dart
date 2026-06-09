import 'dart:io';

import 'package:call_logger/core/services/dictionary_service.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LexiconSpellCheckService variants', () {
    late LexiconSpellCheckService spell;

    setUp(() async {
      spell = LexiconSpellCheckService();
      await spell.init(
        lexiconVariants: {
          'αιτημα': {'αίτημα', 'αίτημά'},
          'γωγω': {'Γωγώ'},
        },
      );
    });

    test('accepts any registered surface with tonos', () {
      expect(spell.isCorrect('αίτημα'), isTrue);
      expect(spell.isCorrect('αίτημά'), isTrue);
      expect(spell.isCorrect('Γωγώ'), isTrue);
    });

    test('rejects unaccented input when accented variants exist', () {
      expect(spell.isCorrect('αιτημα'), isFalse);
      expect(spell.isCorrect('γωγω'), isFalse);
    });

    test('accepts unaccented input when lexicon has only unaccented forms', () async {
      final plain = LexiconSpellCheckService();
      await plain.init(lexiconVariants: {'γωγω': {'γωγω'}});
      expect(plain.isCorrect('γωγω'), isTrue);
      expect(plain.isCorrect('ΓΩΓΩ'), isTrue);
    });

    test('rejects wrong tonos placement', () {
      expect(spell.isCorrect('αιτήμα'), isFalse);
    });

    test('suggestions use primary display form', () {
      final sug = spell.getSuggestions('αιτημ');
      expect(sug, isNotEmpty);
      expect(
        sug.first,
        DictionaryService.primaryDisplayForVariants(
          'αιτημα',
          {'αίτημα', 'αίτημά'},
        ),
      );
    });
  });

  group('DictionaryService variants', () {
    test('ingests multiple surface forms per key', () async {
      final dir = await Directory.systemTemp.createTemp('dict_variants_');
      final file = File('${dir.path}/lexicon.txt');
      await file.writeAsString('αίτημα\nαίτημά\n');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final s = DictionaryService();
      await s.loadFromFile(file.path);
      final variants = s.stripKeyToVariantsMap['αιτημα'];
      expect(variants, isNotNull);
      expect(variants, containsAll(['αίτημα', 'αίτημά']));
    });
  });
}
