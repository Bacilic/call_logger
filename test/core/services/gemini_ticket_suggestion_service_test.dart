// Έλεγχος: GeminiTicketSuggestionService — retry/fallback όπως το παλιό UI mixin.
//
//   flutter test test/core/services/gemini_ticket_suggestion_service_test.dart

import 'package:call_logger/core/services/ai_model_cooldown_registry.dart';
import 'package:call_logger/core/services/ai_ticket_suggestion_service.dart';
import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:call_logger/core/services/gemini_ticket_suggestion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _kTestApiKey = 'test-api-key';
const _kPrimaryModel = 'primary-model';
const _kFallbackModel = 'fallback-model';

const _kPromptTemplate =
    'Πρόβλημα: {Πρόβλημα}\n'
    '{"title":"...","description":"...","solution":"..."}';

const _kTestRequest = AiTicketSuggestionRequest(
  callerText: 'Μαρία',
  equipmentText: '',
  departmentText: 'Ιατρός',
  category: '',
  issue: 'Δοκιμή πρότασης',
  titleText: 'Προσχέδιο',
  notesText: '',
  solutionText: '',
);

String _geminiApiSuccessBody({
  required String title,
  required String description,
  required String solution,
}) {
  return '''
{
  "candidates": [
    {
      "content": {
        "parts": [
          {
            "text": "{\\"title\\":\\"$title\\",\\"description\\":\\"$description\\",\\"solution\\":\\"$solution\\"}"
          }
        ]
      }
    }
  ]
}''';
}

GeminiTicketSuggestionService _service({
  bool fallbackEnabled = true,
  String fallbackModel = _kFallbackModel,
  AiModelCooldownRegistry? cooldownRegistry,
}) {
  return GeminiTicketSuggestionService(
    apiKey: _kTestApiKey,
    endpointTemplate: kDefaultGeminiEndpoint,
    promptTemplate: _kPromptTemplate,
    primaryModel: _kPrimaryModel,
    fallbackEnabled: fallbackEnabled,
    fallbackModel: fallbackModel,
    cooldownRegistry: cooldownRegistry ?? AiModelCooldownRegistry(),
  );
}

bool _urlTargetsModel(Uri url, String modelId) {
  return url.path.contains('/models/$modelId:');
}

void main() {
  group('GeminiTicketSuggestionService.suggest', () {
    test('επιτυχία στην πρώτη προσπάθεια — onModelAttempt μία φορά', () async {
      final client = MockClient((request) async {
        expect(_urlTargetsModel(request.url, _kPrimaryModel), isTrue);
        return http.Response(
          _geminiApiSuccessBody(
            title: 'Title 1',
            description: 'Description 1',
            solution: 'Solution 1',
          ),
          200,
        );
      });
      addTearDown(client.close);

      final attempts = <String>[];
      final result = await _service().suggest(
        _kTestRequest,
        client: client,
        onModelAttempt: attempts.add,
      );

      expect(result.title, 'Title 1');
      expect(result.description, 'Description 1');
      expect(result.solution, 'Solution 1');
      expect(attempts, [_kPrimaryModel]);
    });

    test(
      '503 στο κύριο μοντέλο με ενεργό εφεδρικό — onFallback και επιτυχία εφεδρικού',
      () async {
        var callCount = 0;
        final client = MockClient((request) async {
          callCount++;
          if (callCount == 1) {
            expect(_urlTargetsModel(request.url, _kPrimaryModel), isTrue);
            return http.Response('overloaded', 503);
          }
          return http.Response(
            _geminiApiSuccessBody(
              title: 'Title FB',
              description: 'Description FB',
              solution: 'Solution FB',
            ),
            200,
          );
        });
        addTearDown(client.close);

        final attempts = <String>[];
        String? fallbackFrom;
        String? fallbackTo;

        final result = await _service().suggest(
          _kTestRequest,
          client: client,
          onModelAttempt: attempts.add,
          onFallback: (from, to, reason) {
            fallbackFrom = from;
            fallbackTo = to;
            expect(reason, AiFallbackReason.overloaded);
          },
        );

        expect(result.title, 'Title FB');
        expect(callCount, 2);
        expect(attempts, [_kPrimaryModel, _kFallbackModel]);
        expect(fallbackFrom, _kPrimaryModel);
        expect(fallbackTo, _kFallbackModel);
      },
    );

    test(
      '429 στο κύριο με ενεργό εφεδρικό — onFallback και επιτυχία εφεδρικού',
      () async {
        var callCount = 0;
        final client = MockClient((request) async {
          callCount++;
          if (callCount == 1) {
            expect(_urlTargetsModel(request.url, _kPrimaryModel), isTrue);
            return http.Response(
              '''
{
  "error": {
    "code": 429,
    "message": "Please retry in 48.04768048s."
  }
}''',
              429,
            );
          }
          expect(_urlTargetsModel(request.url, _kFallbackModel), isTrue);
          return http.Response(
            _geminiApiSuccessBody(
              title: 'Title FB',
              description: 'Description FB',
              solution: 'Solution FB',
            ),
            200,
          );
        });
        addTearDown(client.close);

        var fallbackCalled = false;
        AiFallbackReason? fallbackReason;

        final result = await _service().suggest(
          _kTestRequest,
          client: client,
          onFallback: (_, _, reason) {
            fallbackCalled = true;
            fallbackReason = reason;
          },
        );

        expect(result.title, 'Title FB');
        expect(callCount, 2);
        expect(fallbackCalled, isTrue);
        expect(fallbackReason, AiFallbackReason.rateLimited);
      },
    );

    test(
      '403 δεν υποβαθμίζει — infrastructure AiSuggestionException',
      () async {
        final client = MockClient((request) async {
          expect(_urlTargetsModel(request.url, _kPrimaryModel), isTrue);
          return http.Response('forbidden', 403);
        });
        addTearDown(client.close);

        var fallbackCalled = false;

        await expectLater(
          _service().suggest(
            _kTestRequest,
            client: client,
            onFallback: (_, _, _) => fallbackCalled = true,
          ),
          throwsA(
            isA<AiSuggestionException>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having(
                  (e) => e.scope,
                  'scope',
                  AiSuggestionFailureScope.infrastructure,
                ),
          ),
        );
        expect(fallbackCalled, isFalse);
      },
    );

    test(
      'cooldown στο κύριο παρακάμπτει HTTP και δοκιμάζει εφεδρικό',
      () async {
        var now = DateTime(2026, 1, 1, 12, 0, 0);
        final registry = AiModelCooldownRegistry(now: () => now);
        registry.markUnavailable(_kPrimaryModel, const Duration(seconds: 60));

        var callCount = 0;
        final client = MockClient((request) async {
          callCount++;
          expect(_urlTargetsModel(request.url, _kFallbackModel), isTrue);
          return http.Response(
            _geminiApiSuccessBody(
              title: 'FB',
              description: 'D',
              solution: 'S',
            ),
            200,
          );
        });
        addTearDown(client.close);

        AiFallbackReason? reason;
        await _service(cooldownRegistry: registry).suggest(
          _kTestRequest,
          client: client,
          onFallback: (_, _, r) => reason = r,
        );

        expect(callCount, 1);
        expect(reason, AiFallbackReason.cooldown);
      },
    );

    test(
      '503 με απενεργοποιημένο fallback — AiSuggestionException 503',
      () async {
        final client = MockClient((request) async {
          expect(_urlTargetsModel(request.url, _kPrimaryModel), isTrue);
          return http.Response('overloaded', 503);
        });
        addTearDown(client.close);

        await expectLater(
          _service(fallbackEnabled: false).suggest(
            _kTestRequest,
            client: client,
          ),
          throwsA(
            isA<AiSuggestionException>()
                .having((e) => e.statusCode, 'statusCode', 503)
                .having((e) => e.message, 'message', contains('503')),
          ),
        );
      },
    );
  });

  group('GeminiTicketSuggestionService.validateConfiguration', () {
    test('λείπει API key', () {
      final service = GeminiTicketSuggestionService(
        apiKey: '',
        endpointTemplate: kDefaultGeminiEndpoint,
        promptTemplate: _kPromptTemplate,
        primaryModel: _kPrimaryModel,
        fallbackEnabled: false,
        fallbackModel: '',
        cooldownRegistry: AiModelCooldownRegistry(),
      );
      expect(
        service.validateConfiguration(),
        'Ορίστε Gemini API key στις ρυθμίσεις Lansweeper.',
      );
    });

    test('λείπει κύριο μοντέλο', () {
      final service = GeminiTicketSuggestionService(
        apiKey: _kTestApiKey,
        endpointTemplate: kDefaultGeminiEndpoint,
        promptTemplate: _kPromptTemplate,
        primaryModel: '',
        fallbackEnabled: false,
        fallbackModel: '',
        cooldownRegistry: AiModelCooldownRegistry(),
      );
      expect(
        service.validateConfiguration(),
        'Ορίστε κύριο μοντέλο Gemini στις ρυθμίσεις Lansweeper.',
      );
    });
  });
}
