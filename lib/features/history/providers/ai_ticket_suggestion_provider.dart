import 'package:flutter_riverpod/flutter_riverpod.dart';



import '../../../core/services/ai_model_cooldown_registry.dart';

import '../../../core/services/ai_ticket_suggestion_service.dart';

import '../../../core/services/gemini_ticket_suggestion_service.dart';

import 'gemini_settings_provider.dart';



/// Μητρώο cooldown μοντέλων ΤΝ — επιβιώνει μετά το κλείσιμο διαλόγου Lansweeper.

final aiModelCooldownRegistryProvider = Provider<AiModelCooldownRegistry>((ref) {

  return AiModelCooldownRegistry();

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

