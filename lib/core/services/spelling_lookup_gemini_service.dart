import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_prompt_template_syntax.dart';
import 'gemini_json_request.dart';
import 'gemini_ticket_service.dart';

/// Αποτέλεσμα ερώτησης ΤΝ για ορθογραφία λέξης.
class SpellingLookupGeminiResult {
  const SpellingLookupGeminiResult({required this.suggestions, this.note});

  final List<String> suggestions;
  final String? note;
}

/// Η εργοστασιακή προτροπή της «Ερώτησης ΤΝ» — ό,τι έστελνε η εφαρμογή πριν
/// γίνει επεξεργάσιμη, αυτούσιο (απόφαση Διευθυντή 24/10/2026).
const String kDefaultSpellingLookupPrompt = '''
Είσαι βοηθός ορθογραφίας ελληνικών (και όπου χρειάζεται αγγλικών) λέξεων.
Ο χρήστης δίνει μια λέξη ή τμήμα λέξης που δεν είναι σίγουρος για την ορθογραφία της.

Λέξη προς έλεγχο: «{Λέξη}»

Απάντησε ΜΟΝΟ με έγκυρο JSON (χωρίς markdown) της μορφής:
{
  "suggestions": ["μορφή1", "μορφή2"],
  "note": "σύντομη εξήγηση ή κενό string"
}

Κανόνες:
- Έως 5 προτάσεις, μόνο πιθανές σωστές λέξεις (όχι εξήγηση μέσα στις προτάσεις).
- Αν η λέξη είναι ήδη σωστή, επέστρεψε την ίδια ως πρώτη πρόταση.
- Το πεδίο note είναι προαιρετικό (μία σύντομη πρόταση στα ελληνικά).
''';

/// Η «Ερώτηση ΤΝ»: μία λέξη μέσα, προτάσεις και σημείωση πίσω.
const AiPromptProfile kSpellingLookupProfile = AiPromptProfile(
  placeholders: [(token: '{Λέξη}', label: 'Λέξη')],
  jsonResponseKeys: ['suggestions', 'note'],
  jsonKeyLabels: {'suggestions': 'προτάσεις', 'note': 'σημείωση'},
  responseBlueprint: '{"suggestions":["..."],"note":"..."}',
  defaultTemplate: kDefaultSpellingLookupPrompt,
);

/// Κλήση Gemini για προτάσεις ορθογραφίας (μόνο κατόπιν αιτήματος χρήστη).
abstract final class SpellingLookupGeminiService {
  /// Η προτροπή για τη [word]· κενό [template] σημαίνει την εργοστασιακή.
  static String buildPrompt({required String template, required String word}) {
    final source = template.trim().isEmpty
        ? kSpellingLookupProfile.defaultTemplate
        : template;
    return source.replaceAll('{Λέξη}', word.trim());
  }

  static Future<SpellingLookupGeminiResult> suggest({
    required String word,
    required String apiKey,
    required String endpoint,
    String template = '',
    String? primaryModel,
    http.Client? client,
  }) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) {
      throw const GeminiException('Δεν δόθηκε λέξη προς έλεγχο.');
    }

    final text = await GeminiJsonRequest.send(
      prompt: buildPrompt(template: template, word: trimmed),
      apiKey: apiKey,
      endpoint: endpoint,
      model: primaryModel,
      client: client,
      timeout: const Duration(seconds: 30),
    );

    final parsed = _parseSpellingJson(text);
    if (parsed == null) {
      throw const GeminiException(
        'Μη έγκυρη μορφή JSON στην απάντηση Gemini.',
        scope: GeminiFailureScope.model,
      );
    }

    return parsed;
  }

  static SpellingLookupGeminiResult? _parseSpellingJson(String text) {
    final decoded = GeminiJsonRequest.decodeObject(text);
    if (decoded == null) return null;
    final rawList = decoded['suggestions'];
    final suggestions = <String>[];
    if (rawList is List) {
      for (final item in rawList) {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty && !suggestions.contains(s)) {
          suggestions.add(s);
        }
      }
    }
    final note = decoded['note']?.toString().trim();
    if (suggestions.isEmpty && (note == null || note.isEmpty)) return null;
    return SpellingLookupGeminiResult(
      suggestions: suggestions,
      note: note == null || note.isEmpty ? null : note,
    );
  }

  /// Για unit tests χωρίς HTTP.
  @visibleForTesting
  static SpellingLookupGeminiResult? parseResponseJson(String text) =>
      _parseSpellingJson(text);
}
