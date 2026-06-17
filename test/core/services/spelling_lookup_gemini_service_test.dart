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
}
