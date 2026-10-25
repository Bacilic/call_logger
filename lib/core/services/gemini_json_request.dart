import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'gemini_ticket_service.dart';

/// Μία ερώτηση προς το Gemini που περιμένει απάντηση JSON — χωρίς να ξέρει
/// τι ρωτά.
///
/// Στέλνει την έτοιμη προτροπή και επιστρέφει το κείμενο της απάντησης. Κάθε
/// αποτυχία βγαίνει ως [GeminiException] με αιτία, ώστε η αλυσίδα μοντέλων να
/// ξέρει αν αξίζει το επόμενο και ο χρήστης να μη βλέπει ποτέ ωμό κείμενο
/// μηχανής. Το τι σημαίνει η απάντηση το αποφασίζει ο καλών.
abstract final class GeminiJsonRequest {
  static Future<String> send({
    required String prompt,
    required String apiKey,
    required String endpoint,
    String? model,
    http.Client? client,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const GeminiException(
        'Δεν έχει οριστεί Gemini API key.',
        scope: GeminiFailureScope.infrastructure,
      );
    }
    final target = GeminiTicketService.resolveCallTarget(
      endpoint: endpoint,
      apiKey: key,
      primaryModel: model,
    );
    if (!target.uri.hasScheme || target.uri.host.isEmpty) {
      throw const GeminiException(
        'Μη έγκυρο URL endpoint Gemini.',
        scope: GeminiFailureScope.infrastructure,
      );
    }

    final httpClient = client ?? http.Client();
    final http.Response response;
    try {
      try {
        response = await httpClient
            .post(
              target.uri,
              headers: target.headers,
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
            .timeout(timeout);
      } on TimeoutException {
        throw const GeminiException(
          'Η κλήση Gemini έληξε (timeout).',
          scope: GeminiFailureScope.model,
        );
      } on SocketException catch (e) {
        throw GeminiException(
          e.message,
          scope: GeminiFailureScope.infrastructure,
        );
      } on http.ClientException catch (e) {
        throw GeminiException(
          e.message,
          scope: GeminiFailureScope.infrastructure,
        );
      }
    } finally {
      if (client == null) httpClient.close();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final apiMessage = apiErrorMessage(response.body);
      throw GeminiException(
        apiMessage == null
            ? 'Αποτυχία HTTP (${response.statusCode}) κατά την κλήση Gemini.'
            : 'Αποτυχία Gemini (${response.statusCode}): $apiMessage',
        statusCode: response.statusCode,
        scope: GeminiException.classifyFailureScope(
          statusCode: response.statusCode,
          message: apiMessage,
        ),
        retryAfter: GeminiException.extractRetryAfterFromErrorBody(
          response.body,
        ),
      );
    }

    final text = responseText(response.body);
    if (text == null || text.trim().isEmpty) {
      throw const GeminiException(
        'Η απάντηση Gemini ήταν κενή.',
        scope: GeminiFailureScope.model,
      );
    }
    return text;
  }

  /// Το μήνυμα σφάλματος που έστειλε η Google, αν υπάρχει.
  static String? apiErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message']?.toString().trim();
          if (message != null && message.isNotEmpty) return message;
        }
      }
    } on FormatException {
      // Όχι JSON: το σώμα όπως ήρθε είναι το καλύτερο που έχουμε.
    }
    final trimmed = body.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Το κείμενο της πρώτης απάντησης του μοντέλου.
  static String? responseText(String body) {
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
    } on FormatException {
      return null;
    }
  }

  /// Το JSON αντικείμενο της απάντησης — και όταν το μοντέλο το τύλιξε σε
  /// ```json …```, παρά την οδηγία. `null` όταν δεν είναι αντικείμενο JSON.
  static Map<String, dynamic>? decodeObject(String text) {
    var payload = text.trim();
    if (payload.startsWith('```')) {
      payload = payload
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
