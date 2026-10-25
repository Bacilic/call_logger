import 'package:call_logger/core/services/spelling_lookup_gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpellingLookupGeminiService.parseResponseJson', () {
    test('parses suggestions and note', () {
      const raw = '''
{"suggestions":["επιλεγμένος","επιλεγμένη"],"note":"Ρήμα σε μετοχή."}
''';
      final result = SpellingLookupGeminiService.parseResponseJson(raw);
      expect(result, isNotNull);
      expect(result!.suggestions, ['επιλεγμένος', 'επιλεγμένη']);
      expect(result.note, 'Ρήμα σε μετοχή.');
    });

    test('strips markdown code fences', () {
      const raw = '''```json
{"suggestions":["δέντρο"],"note":""}
```''';
      final result = SpellingLookupGeminiService.parseResponseJson(raw);
      expect(result?.suggestions, ['δέντρο']);
    });
  });

  group('SpellingLookupGeminiService.buildPrompt', () {
    test('η προτροπή του χρήστη παίρνει τη λέξη', () {
      expect(
        SpellingLookupGeminiService.buildPrompt(
          template: 'Έλεγξε «{Λέξη}»',
          word: ' ρυθμίστικε ',
        ),
        'Έλεγξε «ρυθμίστικε»',
      );
    });

    test('κενή προτροπή χρήστη σημαίνει την εργοστασιακή', () {
      final prompt = SpellingLookupGeminiService.buildPrompt(
        template: '',
        word: 'δέντρο',
      );
      expect(prompt, startsWith('Είσαι βοηθός ορθογραφίας'));
      expect(prompt, contains('Λέξη προς έλεγχο: «δέντρο»'));
    });
  });
}
