import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeminiTicketService.parseSuggestionJson', () {
    test('διαχωρίζει description και solution', () {
      const json = '''
{"title":"Τίτλος","description":"Πρόβλημα πρόσβασης","solution":"Επαναφορά κωδικού"}''';

      final parsed = GeminiTicketService.parseSuggestionJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.title, 'Τίτλος');
      expect(parsed.description, 'Πρόβλημα πρόσβασης');
      expect(parsed.solution, 'Επαναφορά κωδικού');
    });

    test('επιτρέπει κενό solution (παλιά μορφή JSON)', () {
      const json = '{"title":"Τ","description":"Περιγραφή"}';

      final parsed = GeminiTicketService.parseSuggestionJson(json);

      expect(parsed, isNotNull);
      expect(parsed!.solution, isEmpty);
    });
  });

  group('GeminiTicketService.normalizeSuggestionFields', () {
    test('χωρίζει ενσωματωμένη Λύση από description', () {
      const description = '''Πρόβλημα πρόσβασης στο ΕΚΑΠΥ.

Λύση: Επαναφορά κωδικού μέσω email.''';

      final normalized = GeminiTicketService.normalizeSuggestionFields(
        description: description,
        solution: '',
      );

      expect(normalized.description, contains('Πρόβλημα πρόσβασης'));
      expect(normalized.description, isNot(contains('Λύση:')));
      expect(normalized.solution, contains('Επαναφορά κωδικού'));
    });
  });
}
