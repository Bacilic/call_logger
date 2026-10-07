import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
        GeminiException.classifyFailureScope(
          error: TimeoutException('timeout'),
        ),
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

  group('«Έλεγχος μοντέλων»', () {
    // Επτά μοντέλα· όσα έχουν «zero» στο όνομα απαντούν «ποσόστωση 0». Οι
    // καθυστερήσεις είναι ανάποδες της σειράς, ώστε τα τελευταία να
    // απαντούν πρώτα — το αποτέλεσμα δεν επιτρέπεται να εξαρτάται από αυτό.
    const ids = ['m1', 'm2-zero', 'm3', 'm4', 'm5-zero', 'm6', 'm7'];

    ({
      http.Client client,
      Map<String, int> asked,
      List<Uri> lists,
      int Function() peak,
    })
    fakeGoogle() {
      final asked = <String, int>{};
      final lists = <Uri>[];
      var running = 0;
      var peak = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          lists.add(request.url);
          return http.Response(
            jsonEncode({
              'models': [
                for (final id in ids)
                  {
                    'name': 'models/$id',
                    'displayName': id,
                    'supportedGenerationMethods': ['generateContent'],
                  },
              ],
            }),
            200,
          );
        }
        final id = RegExp(r'models/([^:]+):').firstMatch(request.url.path)![1]!;
        asked[id] = (asked[id] ?? 0) + 1;
        running++;
        if (running > peak) peak = running;
        await Future<void>.delayed(
          Duration(milliseconds: 5 * (ids.length - ids.indexOf(id))),
        );
        running--;
        if (id.contains('zero')) {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Quota exceeded, limit: 0'},
            }),
            429,
          );
        }
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text':
                          '{"title":"OK","description":"OK","solution":"OK"}',
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      return (client: client, asked: asked, lists: lists, peak: () => peak);
    }

    test(
      'κάθε μοντέλο ρωτιέται μία φορά, παράλληλα, με σταθερό αποτέλεσμα',
      () async {
        final google = fakeGoogle();

        final result = await GeminiTicketService.probeModelsWithQuota(
          apiKey: 'ΚΛΕΙΔΙ',
          client: google.client,
        );

        expect(google.asked, {for (final id in ids) id: 1});
        expect(result.availableModels.map((m) => m.id), [
          'm1',
          'm3',
          'm4',
          'm6',
          'm7',
        ]);
        expect(result.totalChecked, ids.length);
        expect(google.peak(), greaterThan(1), reason: 'Όχι ένα-ένα');
        expect(google.peak(), lessThanOrEqualTo(kGeminiProbeConcurrency));
      },
    );

    test('η λίστα μοντέλων έρχεται με μία ερώτηση', () async {
      final google = fakeGoogle();

      await GeminiTicketService.listTextModels(
        apiKey: 'ΚΛΕΙΔΙ',
        client: google.client,
      );

      expect(google.lists, hasLength(1));
      expect(
        google.lists.single.queryParameters['pageSize'],
        '$kGeminiModelsPageSize',
      );
    });
  });
}
