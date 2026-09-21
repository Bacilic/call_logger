import 'package:http/http.dart' as http;

import 'ai_model_chain_runner.dart';
import 'ai_model_cooldown_registry.dart';
import 'gemini_runtime_settings.dart';
import 'gemini_ticket_service.dart';
import 'spelling_lookup_gemini_service.dart';

/// Η «Ερώτηση ΤΝ» της Ορθογραφίας, με την ίδια αντοχή που έχει η Πρόταση ΤΝ.
///
/// Ρωτά πρώτα τη μνήμη υγείας του υπολογιστή και ξεκινά από το μοντέλο που δεν
/// ξέρει πεσμένο· αν αποτύχει, δοκιμάζει το εφεδρικό της ίδιας ρύθμισης. Όταν
/// δεν μένει τίποτα, λέει καθαρά γιατί και ως πότε.
abstract final class SpellingLookupAiService {
  static const String taskLabel = 'τον ορθογραφικό έλεγχο';

  static Future<SpellingLookupGeminiResult> suggest({
    required String word,
    required GeminiRuntimeSettings settings,
    required AiModelCooldownRegistry registry,
    http.Client? client,
  }) {
    return AiModelChainRunner(
      registry: registry,
    ).run<SpellingLookupGeminiResult>(
      models: settings.candidateModels,
      taskLabel: taskLabel,
      attempt: (model) => SpellingLookupGeminiService.suggest(
        word: word,
        apiKey: settings.apiKey,
        endpoint: settings.endpoint,
        primaryModel: model,
        client: client,
      ),
      classify: classifyFailure,
    );
  }

  /// Μεταφράζει μια αποτυχία Gemini σε γλώσσα που καταλαβαίνει η αλυσίδα.
  static AiModelAttemptFailure classifyFailure(Object error) {
    if (error is! GeminiException) {
      return AiModelAttemptFailure(
        message: 'Η ερώτηση ΤΝ δεν ολοκληρώθηκε.',
        reason: AiModelDownReason.unavailable,
        fatal: true,
      );
    }

    final scope =
        error.scope ??
        GeminiException.classifyFailureScope(
          statusCode: error.statusCode,
          message: error.message,
        );

    return AiModelAttemptFailure(
      message: error.message,
      reason: switch (error.statusCode) {
        404 => AiModelDownReason.modelNotFound,
        429 => AiModelDownReason.quotaExhausted,
        _ => AiModelDownReason.unavailable,
      },
      serverRetryAfter: error.retryAfter,
      // Ρύθμιση ή δίκτυο: το εφεδρικό θα σκοντάψει στο ίδιο εμπόδιο.
      fatal: scope == GeminiFailureScope.infrastructure,
    );
  }
}
