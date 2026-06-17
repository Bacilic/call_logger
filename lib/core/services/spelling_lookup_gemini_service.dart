import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'gemini_ticket_service.dart';

/// Αποτέλεσμα ερώτησης ΤΝ για ορθογραφία λέξης.
class SpellingLookupGeminiResult {
  const SpellingLookupGeminiResult({
    required this.suggestions,
    this.note,
  });

  final List<String> suggestions;
  final String? note;
}

/// Κλήση Gemini για προτάσεις ορθογραφίας (μόνο κατόπιν αιτήματος χρήστη).
abstract final class SpellingLookupGeminiService {
  static const String _promptTemplate = '''
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

  static Future<SpellingLookupGeminiResult> suggest({
    required String word,
    required String apiKey,
    required String endpoint,
    String? primaryModel,
    http.Client? client,
  }) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) {
      throw const GeminiException('Δεν δόθηκε λέξη προς έλεγχο.');
    }

    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const GeminiException('Δεν έχει οριστεί Gemini API key.');
    }

    final resolvedEndpoint = GeminiTicketService.resolveEndpoint(
      endpoint: endpoint,
      apiKey: key,
      primaryModel: primaryModel,
    );
    final uri = Uri.tryParse(resolvedEndpoint);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const GeminiException('Μη έγκυρο URL endpoint Gemini.');
    }

    final prompt = _promptTemplate.replaceAll('{Λέξη}', trimmed);

    final httpClient = client ?? http.Client();
    final http.Response response;
    try {
      response = await httpClient
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'contents': [
                <String, dynamic>{
                  'parts': [
                    <String, String>{'text': prompt},
                  ],
                },
              ],
              'generationConfig': <String, String>{
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
    } finally {
      if (client == null) httpClient.close();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final apiMessage = _extractApiErrorMessage(response.body);
      throw GeminiException(
        apiMessage == null
            ? 'Αποτυχία HTTP (${response.statusCode}) κατά την κλήση Gemini.'
            : 'Αποτυχία Gemini (${response.statusCode}): $apiMessage',
        statusCode: response.statusCode,
      );
    }

    final text = _extractResponseText(response.body);
    if (text == null || text.trim().isEmpty) {
      throw const GeminiException('Η απάντηση Gemini ήταν κενή.');
    }

    final parsed = _parseSpellingJson(text);
    if (parsed == null) {
      throw const GeminiException('Μη έγκυρη μορφή JSON στην απάντηση Gemini.');
    }

    return parsed;
  }

  static String? _extractApiErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message']?.toString().trim();
          if (message != null && message.isNotEmpty) return message;
        }
      }
    } catch (_) {}
    final trimmed = body.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _extractResponseText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map) return null;
      final content = first['content'];
      if (content is! Map) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final part = parts.first;
      if (part is! Map) return null;
      return part['text']?.toString();
    } catch (_) {
      return null;
    }
  }

  static SpellingLookupGeminiResult? _parseSpellingJson(String text) {
    try {
      var payload = text.trim();
      if (payload.startsWith('```')) {
        payload = payload
            .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
            .replaceFirst(RegExp(r'\s*```$'), '');
      }
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
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
    } catch (_) {
      return null;
    }
  }

  /// Για unit tests χωρίς HTTP.
  @visibleForTesting
  static SpellingLookupGeminiResult? parseResponseJson(String text) =>
      _parseSpellingJson(text);
}
