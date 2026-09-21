import 'package:call_logger/core/services/ai_model_cooldown_registry.dart';
import 'package:call_logger/core/services/gemini_runtime_settings.dart';
import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:call_logger/core/services/spelling_lookup_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

GeminiRuntimeSettings _settings({
  String primary = 'κύριο',
  String fallback = 'εφεδρικό',
  bool fallbackEnabled = true,
}) {
  return GeminiRuntimeSettings(
    apiKey: 'κλειδί',
    endpoint: 'https://example.test/v1/models/{model}:generateContent',
    primaryModel: primary,
    fallbackEnabled: fallbackEnabled,
    fallbackModel: fallback,
  );
}

void main() {
  group('GeminiRuntimeSettings.candidateModels', () {
    test('κύριο και εφεδρικό, με αυτή τη σειρά', () {
      expect(_settings().candidateModels, ['κύριο', 'εφεδρικό']);
    });

    test('κλειστή εφεδρεία αφήνει μόνο το κύριο', () {
      expect(_settings(fallbackEnabled: false).candidateModels, ['κύριο']);
    });

    test('ίδιο εφεδρικό με το κύριο δεν διπλογράφεται', () {
      expect(_settings(fallback: 'κύριο').candidateModels, ['κύριο']);
    });

    test('κενό εφεδρικό αφήνει μόνο το κύριο', () {
      expect(_settings(fallback: '   ').candidateModels, ['κύριο']);
    });
  });

  group('SpellingLookupAiService.classifyFailure', () {
    test('εξαντλημένη ποσόστωση, με τον χρόνο του διακομιστή', () {
      final failure = SpellingLookupAiService.classifyFailure(
        const GeminiException(
          'ποσόστωση',
          statusCode: 429,
          retryAfter: Duration(minutes: 34),
        ),
      );

      expect(failure.reason, AiModelDownReason.quotaExhausted);
      expect(failure.serverRetryAfter, const Duration(minutes: 34));
      expect(failure.fatal, isFalse);
    });

    test('ανύπαρκτο μοντέλο', () {
      final failure = SpellingLookupAiService.classifyFailure(
        const GeminiException('δεν υπάρχει', statusCode: 404),
      );

      expect(failure.reason, AiModelDownReason.modelNotFound);
      expect(failure.fatal, isFalse);
    });

    test('λάθος κλειδί σταματά την αλυσίδα', () {
      final failure = SpellingLookupAiService.classifyFailure(
        const GeminiException('άκυρο κλειδί', statusCode: 403),
      );

      expect(failure.fatal, isTrue);
    });

    test('λήξη χρόνου αφήνει το εφεδρικό να δοκιμάσει', () {
      final failure = SpellingLookupAiService.classifyFailure(
        const GeminiException(
          'Η κλήση Gemini έληξε (timeout).',
          scope: GeminiFailureScope.model,
        ),
      );

      expect(failure.reason, AiModelDownReason.unavailable);
      expect(failure.fatal, isFalse);
    });

    test('άγνωστο σφάλμα δεν διαρρέει ωμό κείμενο μηχανής', () {
      final failure = SpellingLookupAiService.classifyFailure(
        StateError('Bad state: no element'),
      );

      expect(failure.message, isNot(contains('Bad state')));
      expect(failure.fatal, isTrue);
    });
  });
}
