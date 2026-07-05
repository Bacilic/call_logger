import 'package:http/http.dart' as http;



import 'ai_model_cooldown_registry.dart';

import 'ai_ticket_suggestion_service.dart';

import 'gemini_ticket_service.dart';



/// Υλοποίηση [AiTicketSuggestionService] μέσω Gemini API.

class GeminiTicketSuggestionService implements AiTicketSuggestionService {

  const GeminiTicketSuggestionService({

    required this.apiKey,

    required this.endpointTemplate,

    required this.promptTemplate,

    required this.primaryModel,

    required this.fallbackEnabled,

    required this.fallbackModel,

    required this.cooldownRegistry,

  });



  final String apiKey;

  final String endpointTemplate;

  final String promptTemplate;

  final String primaryModel;

  final bool fallbackEnabled;

  final String fallbackModel;

  final AiModelCooldownRegistry cooldownRegistry;



  @override

  String? validateConfiguration() {

    if (apiKey.trim().isEmpty) {

      return 'Ορίστε Gemini API key στις ρυθμίσεις Lansweeper.';

    }

    if (primaryModel.trim().isEmpty) {

      return 'Ορίστε κύριο μοντέλο Gemini στις ρυθμίσεις Lansweeper.';

    }

    return null;

  }



  @override

  String buildPrompt(AiTicketSuggestionRequest request) {

    return GeminiTicketService.buildPrompt(

      promptTemplate: promptTemplate,

      callerText: request.callerText,

      equipmentText: request.equipmentText,

      departmentText: request.departmentText,

      category: request.category,

      issue: request.issue,

      titleText: request.titleText,

      notesText: request.notesText,

      solutionText: request.solutionText,

    );

  }



  AiFallbackReason _fallbackReasonFor(GeminiException e) {

    switch (e.statusCode) {

      case 429:

        return AiFallbackReason.rateLimited;

      case 503:

        return AiFallbackReason.overloaded;

      default:

        return AiFallbackReason.modelFailure;

    }

  }



  Never _throwCooldownExhausted(List<String> modelIds) {

    final earliest = cooldownRegistry.earliestAvailable(modelIds);

    throw AiSuggestionException(

      earliest == null

          ? 'Δεν ήταν δυνατή η πρόταση ΤΝ — όλα τα μοντέλα είναι σε αναμονή ποσόστωσης.'

          : 'Τα μοντέλα ΤΝ είναι σε αναμονή ποσόστωσης. '

              'Δοκιμάστε ξανά μετά τις '

              '${earliest.availableAt.hour.toString().padLeft(2, '0')}:'

              '${earliest.availableAt.minute.toString().padLeft(2, '0')}:'

              '${earliest.availableAt.second.toString().padLeft(2, '0')}.',

      scope: AiSuggestionFailureScope.model,

      retryAvailableAt: earliest?.availableAt,

      waitingModel: earliest?.model,

    );

  }



  @override

  Future<AiTicketSuggestion> suggest(

    AiTicketSuggestionRequest request, {

    required http.Client client,

    void Function(String model)? onModelAttempt,

    void Function(String fromModel, String toModel, AiFallbackReason reason)?

        onFallback,

  }) async {

    final trimmedKey = apiKey.trim();

    final trimmedPrimary = primaryModel.trim();

    final trimmedFallback = fallbackModel.trim();



    final attempts = <({String model, String endpoint})>[

      (

        model: trimmedPrimary,

        endpoint: GeminiTicketService.resolveEndpoint(

          endpoint: endpointTemplate,

          apiKey: trimmedKey,

          primaryModel: trimmedPrimary,

        ),

      ),

    ];

    if (fallbackEnabled &&
        trimmedFallback.isNotEmpty &&
        trimmedFallback != trimmedPrimary) {
      attempts.add((
        model: trimmedFallback,
        endpoint: GeminiTicketService.resolveEndpoint(
          endpoint: endpointTemplate,
          apiKey: trimmedKey,
          primaryModel: trimmedFallback,
        ),
      ));
    }



    final modelIds = attempts.map((a) => a.model).toList();

    var anyAttempted = false;



    for (var i = 0; i < attempts.length; i++) {

      final attempt = attempts[i];

      final isLast = i == attempts.length - 1;



      if (cooldownRegistry.isInCooldown(attempt.model)) {

        if (!isLast) {

          onFallback?.call(

            attempt.model,

            attempts[i + 1].model,

            AiFallbackReason.cooldown,

          );

          continue;

        }

        continue;

      }



      onModelAttempt?.call(attempt.model);

      anyAttempted = true;

      try {

        final result = await GeminiTicketService.suggest(

          apiKey: trimmedKey,

          endpoint: attempt.endpoint,

          promptTemplate: promptTemplate,

          callerText: request.callerText,

          equipmentText: request.equipmentText,

          departmentText: request.departmentText,

          category: request.category,

          issue: request.issue,

          titleText: request.titleText,

          notesText: request.notesText,

          solutionText: request.solutionText,

          client: client,

        );

        return (

          title: result.title,

          description: result.description,

          solution: result.solution,

        );

      } on GeminiException catch (e) {

        if (e.retryAfter != null) {

          cooldownRegistry.markUnavailable(attempt.model, e.retryAfter!);

        }



        final scope = e.scope ??

            GeminiException.classifyFailureScope(

              statusCode: e.statusCode,

              message: e.message,

            );



        if (scope == GeminiFailureScope.infrastructure) {

          throw AiSuggestionException(

            e.message,

            statusCode: e.statusCode,

            scope: AiSuggestionFailureScope.infrastructure,

          );

        }



        if (!isLast) {

          onFallback?.call(

            attempt.model,

            attempts[i + 1].model,

            _fallbackReasonFor(e),

          );

          continue;

        }

        final availableAt = cooldownRegistry.availableAt(attempt.model);

        throw AiSuggestionException(

          e.message,

          statusCode: e.statusCode,

          scope: AiSuggestionFailureScope.model,

          retryAvailableAt: availableAt,

          waitingModel: availableAt != null ? attempt.model : null,

        );

      }

    }



    if (!anyAttempted || cooldownRegistry.earliestAvailable(modelIds) != null) {

      _throwCooldownExhausted(modelIds);

    }



    throw const AiSuggestionException(

      'Δεν ήταν δυνατή η πρόταση ΤΝ — δεν υπάρχουν διαθέσιμα μοντέλα.',

      scope: AiSuggestionFailureScope.model,

    );

  }

}

