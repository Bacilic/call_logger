import 'package:http/http.dart' as http;

import '../../../core/services/ai_model_chain_runner.dart';
import '../../../core/services/ai_model_cooldown_registry.dart';
import '../../../core/services/gemini_json_request.dart';
import '../../../core/services/gemini_runtime_settings.dart';
import '../../../core/services/gemini_ticket_service.dart';
import '../../../core/services/spelling_lookup_ai_service.dart';
import 'knowledge_ai_prompts.dart';

/// Η «Βελτίωση με ΤΝ» ενός άρθρου, με την ίδια αντοχή που έχουν η Πρόταση ΤΝ
/// και η Ορθογραφία: πρώτα το μοντέλο που δεν είναι γνωστό πεσμένο, μετά το
/// εφεδρικό, και όταν δεν μένει τίποτα, καθαρά γιατί και ως πότε.
abstract final class KnowledgeAiService {
  static const String taskLabel = 'τη βελτίωση του άρθρου';

  /// Στέλνει την έτοιμη [prompt] και επιστρέφει όσα πεδία πρότεινε η ΤΝ.
  ///
  /// Δεν γράφει τίποτα στη βάση: η φόρμα δείχνει την πρόταση και αποθηκεύει
  /// μόνο όταν το ζητήσει ο χρήστης.
  static Future<KnowledgeImproveSuggestion> improve({
    required String prompt,
    required GeminiRuntimeSettings settings,
    required AiModelCooldownRegistry registry,
    http.Client? client,
  }) {
    return AiModelChainRunner(
      registry: registry,
    ).run<KnowledgeImproveSuggestion>(
      models: settings.candidateModels,
      taskLabel: taskLabel,
      attempt: (model) async {
        final text = await GeminiJsonRequest.send(
          prompt: prompt,
          apiKey: settings.apiKey,
          endpoint: settings.endpoint,
          model: model,
          client: client,
        );
        final suggestion = parseKnowledgeImproveResponse(text);
        if (suggestion == null) {
          // Το μοντέλο απάντησε, αλλά όχι με τα πεδία που ζητά η προτροπή —
          // το εφεδρικό μπορεί να τα καταφέρει.
          throw const GeminiException(
            'Η απάντηση της ΤΝ δεν είχε τα πεδία του άρθρου (title, symptom, '
            'solution, tags). Ελέγξτε τη μορφή JSON στην προτροπή.',
            scope: GeminiFailureScope.model,
          );
        }
        return suggestion;
      },
      // Η ίδια ανάγνωση αποτυχιών με την Ορθογραφία: η αιτία μιας κλήσης
      // Gemini δεν εξαρτάται από το τι ρωτήθηκε.
      classify: SpellingLookupAiService.classifyFailure,
    );
  }
}
