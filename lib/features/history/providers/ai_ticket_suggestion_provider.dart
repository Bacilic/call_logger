import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/ai_model_cooldown_registry.dart';

import '../../../core/services/ai_model_health_store.dart';

import '../../../core/services/ai_ticket_suggestion_service.dart';

import '../../../core/services/gemini_ticket_suggestion_service.dart';

import 'gemini_settings_provider.dart';

/// Η υγεία των μοντέλων ΤΝ — επιβιώνει και του κλεισίματος της εφαρμογής.
///
/// Η γνώση φορτώνεται από τον υπολογιστή στο παρασκήνιο και ξαναγράφεται σε
/// κάθε μεταβολή. Μια κλήση που προλαβαίνει τη φόρτωση απλώς δεν ξέρει ακόμη —
/// κοστίζει μία δοκιμή, μία φορά ανά εκκίνηση.

final aiModelCooldownRegistryProvider = Provider<AiModelCooldownRegistry>((
  ref,
) {
  late final AiModelCooldownRegistry registry;
  registry = AiModelCooldownRegistry(
    onChanged: () =>
        unawaited(AiModelHealthStore.save(registry.activeDowntimes)),
  );
  unawaited(AiModelHealthStore.load().then(registry.restore));
  return registry;
});

/// Πάροχος υπηρεσίας πρότασης ticket· σήμερα Gemini, μελλοντικά άλλοι πάροχοι.

final aiTicketSuggestionServiceProvider =
    Provider.autoDispose<AiTicketSuggestionService>((ref) {
      return GeminiTicketSuggestionService(
        apiKey: ref.watch(geminiApiKeyProvider),

        endpointTemplate: ref.watch(geminiEndpointProvider),

        promptTemplate: ref.watch(geminiPromptTemplateProvider),

        primaryModel: ref.watch(geminiPrimaryModelProvider),

        fallbackEnabled: ref.watch(geminiFallbackEnabledProvider),

        fallbackModel: ref.watch(geminiFallbackModelProvider),

        cooldownRegistry: ref.watch(aiModelCooldownRegistryProvider),
      );
    });
