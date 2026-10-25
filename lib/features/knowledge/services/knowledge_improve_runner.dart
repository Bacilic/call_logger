import 'package:flutter/services.dart';

import '../../../core/services/ai_model_chain_runner.dart';
import '../../../core/services/ai_model_cooldown_registry.dart';
import '../../../core/services/gemini_runtime_settings.dart';
import 'knowledge_ai_prompt_store.dart';
import 'knowledge_ai_prompts.dart';
import 'knowledge_ai_service.dart';

/// Τι έγινε με το «Βελτίωση με ΤΝ».
sealed class KnowledgeImproveOutcome {
  const KnowledgeImproveOutcome();
}

/// Η ΤΝ απάντησε· τα πεδία της πρότασης μπαίνουν στη φόρμα.
final class KnowledgeImproved extends KnowledgeImproveOutcome {
  const KnowledgeImproved(this.suggestion);

  final KnowledgeImproveSuggestion suggestion;
}

/// Δεν υπάρχει ρυθμισμένη ΤΝ: το άρθρο με την προτροπή πήγε στο πρόχειρο,
/// για επικόλληση σε όποια ΤΝ θέλει ο χρήστης.
final class KnowledgeImproveCopied extends KnowledgeImproveOutcome {
  const KnowledgeImproveCopied();
}

/// Η ΤΝ δεν απάντησε όπως έπρεπε — το [message] λέει γιατί.
final class KnowledgeImproveFailed extends KnowledgeImproveOutcome {
  const KnowledgeImproveFailed(this.message);

  final String message;
}

/// Τα πεδία του άρθρου όπως είναι αυτή τη στιγμή στη φόρμα.
typedef KnowledgeImproveInput = ({
  String title,
  String symptom,
  String solution,
  String tags,
});

/// Η «Βελτίωση με ΤΝ» από άκρη σε άκρη, χωρίς UI: διαβάζει την προτροπή του
/// χρήστη, τη συμπληρώνει με το άρθρο και ρωτά την ΤΝ — ή, χωρίς κλειδί ΤΝ,
/// αντιγράφει την προτροπή στο πρόχειρο. Δεν γράφει ποτέ στη βάση.
Future<KnowledgeImproveOutcome> runKnowledgeImprove(
  KnowledgeImproveInput input, {
  required AiModelCooldownRegistry registry,
}) async {
  final prompt = buildKnowledgeImprovePrompt(
    template: await KnowledgePrompt.improve.read(),
    title: input.title,
    symptom: input.symptom,
    solution: input.solution,
    tags: input.tags,
  );
  final settings = await GeminiRuntimeSettings.loadFromDatabase();
  if (settings.apiKey.trim().isEmpty) {
    await Clipboard.setData(ClipboardData(text: prompt));
    return const KnowledgeImproveCopied();
  }
  try {
    return KnowledgeImproved(
      await KnowledgeAiService.improve(
        prompt: prompt,
        settings: settings,
        registry: registry,
      ),
    );
  } on AiModelChainException catch (e) {
    return KnowledgeImproveFailed(e.message);
  }
}
