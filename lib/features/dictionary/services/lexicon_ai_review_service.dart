import 'package:http/http.dart' as http;

import '../../../core/services/ai_model_chain_runner.dart';
import '../../../core/services/ai_model_cooldown_registry.dart';
import '../../../core/services/gemini_json_request.dart';
import '../../../core/services/gemini_runtime_settings.dart';
import '../../../core/services/gemini_ticket_service.dart';
import '../../../core/services/spelling_lookup_ai_service.dart';
import 'lexicon_ai_prompt_store.dart';
import 'lexicon_ai_prompts.dart';

/// Τι έγινε με τον «Έλεγχο με ΤΝ».
sealed class LexiconAiReviewOutcome {
  const LexiconAiReviewOutcome();
}

/// Η ΤΝ απάντησε· οι ετυμηγορίες ανά αριθμό λέξης (από το 1).
final class LexiconAiReviewed extends LexiconAiReviewOutcome {
  const LexiconAiReviewed(this.verdicts);

  final Map<int, LexiconAiVerdict> verdicts;
}

/// Η ΤΝ δεν απάντησε όπως έπρεπε — το [message] λέει γιατί.
final class LexiconAiReviewFailed extends LexiconAiReviewOutcome {
  const LexiconAiReviewFailed(this.message);

  final String message;
}

/// Ο μαζικός έλεγχος λέξεων, με την ίδια αντοχή που έχουν η Πρόταση ΤΝ και η
/// Ορθογραφία: πρώτα το μοντέλο που δεν είναι γνωστό πεσμένο, μετά το
/// εφεδρικό. Δεν γράφει ποτέ στη βάση — αποφασίζει ο χρήστης.
abstract final class LexiconAiReviewService {
  static const String taskLabel = 'τον έλεγχο λέξεων';

  static Future<LexiconAiReviewOutcome> review(
    List<String> words, {
    required AiModelCooldownRegistry registry,
    http.Client? client,
  }) async {
    final prompt = buildLexiconReviewPrompt(
      template: await LexiconPrompt.review.read(),
      words: words,
    );
    final settings = await GeminiRuntimeSettings.loadFromDatabase();
    if (settings.apiKey.trim().isEmpty) {
      return const LexiconAiReviewFailed(
        'Δεν έχει οριστεί Gemini API key (Ιστορικό → Lansweeper).',
      );
    }
    try {
      return LexiconAiReviewed(
        await AiModelChainRunner(
          registry: registry,
        ).run<Map<int, LexiconAiVerdict>>(
          models: settings.candidateModels,
          taskLabel: taskLabel,
          attempt: (model) async {
            final text = await GeminiJsonRequest.send(
              prompt: prompt,
              apiKey: settings.apiKey,
              endpoint: settings.endpoint,
              model: model,
              client: client,
              // Διακόσιες λέξεις θέλουν χρόνο να κριθούν.
              timeout: const Duration(seconds: 120),
            );
            final verdicts = parseLexiconReviewResponse(
              text,
              wordCount: words.length,
            );
            if (verdicts == null) {
              // Το μοντέλο απάντησε, αλλά όχι στη μορφή που ζητά η
              // προτροπή — το εφεδρικό μπορεί να τα καταφέρει.
              throw const GeminiException(
                'Η απάντηση της ΤΝ δεν είχε ετυμηγορίες (results με n, '
                'verdict, suggestion). Ελέγξτε τη μορφή JSON στην '
                'προτροπή.',
                scope: GeminiFailureScope.model,
              );
            }
            return verdicts;
          },
          classify: SpellingLookupAiService.classifyFailure,
        ),
      );
    } on AiModelChainException catch (e) {
      return LexiconAiReviewFailed(e.message);
    }
  }
}
