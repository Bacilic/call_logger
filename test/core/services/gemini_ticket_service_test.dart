import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('GeminiException.extractRetryAfterFromErrorBody', () {
    test('εξάγει retryDelay από RetryInfo details', () {
      const body = '''
{
  "error": {
    "code": 429,
    "message": "Quota exceeded",
    "details": [
      {
        "@type": "type.googleapis.com/google.rpc.RetryInfo",
        "retryDelay": "48.047s"
      }
    ]
  }
}''';

      final retryAfter = GeminiException.extractRetryAfterFromErrorBody(body);

      expect(retryAfter, const Duration(seconds: 50));
    });

    test('εξάγει retry από κείμενο μηνύματος με στρογγυλοποίηση +1 δλ', () {
      const body = '''
{
  "error": {
    "code": 429,
    "message": "Please retry in 48.04768048s."
  }
}''';

      final retryAfter = GeminiException.extractRetryAfterFromErrorBody(body);

      expect(retryAfter, const Duration(seconds: 50));
    });

    test('επιστρέφει null όταν λείπει retry πληροφορία', () {
      const body = '{"error":{"code":500,"message":"internal"}}';

      expect(GeminiException.extractRetryAfterFromErrorBody(body), isNull);
    });
  });

  group('GeminiException.classifyFailureScope', () {
    test('model για 429/503/500/404', () {
      for (final code in [404, 429, 500, 503]) {
        expect(
          GeminiException.classifyFailureScope(statusCode: code),
          GeminiFailureScope.model,
        );
      }
    });

    test('infrastructure για 400/401/403', () {
      for (final code in [400, 401, 403]) {
        expect(
          GeminiException.classifyFailureScope(statusCode: code),
          GeminiFailureScope.infrastructure,
        );
      }
    });

    test('model για TimeoutException και κενή/άκυρη απάντηση', () {
      expect(
        GeminiException.classifyFailureScope(error: TimeoutException('timeout')),
        GeminiFailureScope.model,
      );
      expect(
        GeminiException.classifyFailureScope(
          message: 'Η απάντηση Gemini ήταν κενή.',
        ),
        GeminiFailureScope.model,
      );
      expect(
        GeminiException.classifyFailureScope(
          message: 'Μη έγκυρη μορφή JSON στην απάντηση Gemini.',
        ),
        GeminiFailureScope.model,
      );
    });

    test('infrastructure για δίκτυο και ρυθμίσεις', () {
      expect(
        GeminiException.classifyFailureScope(
          error: const SocketException('network'),
        ),
        GeminiFailureScope.infrastructure,
      );
      expect(
        GeminiException.classifyFailureScope(
          error: http.ClientException('client'),
        ),
        GeminiFailureScope.infrastructure,
      );
      expect(
        GeminiException.classifyFailureScope(
          message: 'Δεν έχει οριστεί Gemini API key.',
        ),
        GeminiFailureScope.infrastructure,
      );
      expect(
        GeminiException.classifyFailureScope(
          message: 'Μη έγκυρο URL endpoint Gemini.',
        ),
        GeminiFailureScope.infrastructure,
      );
    });
  });

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
