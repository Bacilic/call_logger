import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/ai_model_health_provider.dart';

import '../../../core/services/ai_ticket_suggestion_service.dart';

import '../../../core/services/gemini_ticket_suggestion_service.dart';

import 'gemini_settings_provider.dart';

/// Η μνήμη υγείας μοντέλων ζει πλέον στο `core` — κοινή για κάθε οθόνη που
/// μιλά στην ΤΝ. Η επανεξαγωγή κρατά τους παλιούς καλούντες αμετάβλητους.
export '../../../core/providers/ai_model_health_provider.dart'
    show aiModelCooldownRegistryProvider;

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
