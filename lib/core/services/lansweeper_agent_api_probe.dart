import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lansweeper_ticket_requester_fields.dart';

/// Αποτέλεσμα δοκιμής πράκτορα μέσω Ticket API (`AddTicket`).
///
/// Το Lansweeper δεν εκθέτει ξεχωριστό endpoint επαλήθευσης· η δοκιμή στέλνει
/// πραγματικό αίτημα. Αν η απάντηση είναι επιτυχής, δημιουργείται ticket που
/// μπορείτε να διαγράψετε στο Help Desk.
class LansweeperAgentApiProbeResult {
  const LansweeperAgentApiProbeResult({
    required this.ok,
    required this.message,
  });

  final bool ok;
  final String message;
}

abstract final class LansweeperAgentApiProbe {
  static const String _probeSubject = '[Call Logger] Έλεγχος πράκτορα API';
  static const String _probeDescription =
      'Αυτόματη δοκιμή ρυθμίσεων από την εφαρμογή Call Logger.\n'
      'Μπορείτε να διαγράψετε αυτό το αίτημα στο Help Desk.';

  static Future<LansweeperAgentApiProbeResult> verify({
    required String apiUrl,
    required String apiKey,
    required String agentUsername,
  }) async {
    final url = apiUrl.trim();
    final key = apiKey.trim();
    final agent = agentUsername.trim();

    if (url.isEmpty) {
      return const LansweeperAgentApiProbeResult(
        ok: false,
        message: 'Συμπληρώστε το URL API (api.aspx).',
      );
    }
    if (key.isEmpty) {
      return const LansweeperAgentApiProbeResult(
        ok: false,
        message: 'Συμπληρώστε το Lansweeper API key.',
      );
    }
    if (agent.isEmpty) {
      return const LansweeperAgentApiProbeResult(
        ok: false,
        message: 'Συμπληρώστε το όνομα πράκτορα (username).',
      );
    }

    final baseUri = Uri.tryParse(url);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      return LansweeperAgentApiProbeResult(
        ok: false,
        message: 'Μη έγκυρο Lansweeper API URL: $url',
      );
    }

    final uri = baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        'action': 'AddTicket',
        'key': key,
      },
    );

    final form = <String, String>{
      'Subject': _probeSubject,
      'Description': _probeDescription,
      ...lansweeperAgentAsMatchingRequesterFields(agent),
    };

    final client = HttpClient();
    try {
      final httpRequest = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      httpRequest.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      httpRequest.write(Uri(queryParameters: form).query);
      final response = await httpRequest.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LansweeperAgentApiProbeResult(
          ok: false,
          message:
              'Αποτυχία HTTP (${response.statusCode}). ${body.trim().isEmpty ? '' : body.trim()}',
        );
      }

      final payload = _tryDecodeJson(body);
      final success = _payloadSuccess(payload);
      final serverMessage = _payloadMessage(payload) ?? body.trim();
      final ticketId = _payloadTicketId(payload);

      if (success) {
        final idLine = ticketId != null && ticketId.isNotEmpty
            ? ' Ticket ID: $ticketId.'
            : '';
        return LansweeperAgentApiProbeResult(
          ok: true,
          message:
              'Ο πράκτορας αναγνωρίστηκε από το API.$idLine '
              'Δημιουργήθηκε δοκιμαστικό αίτημα — διαγράψτε το στο Help Desk αν δεν το χρειάζεστε.',
        );
      }

      return LansweeperAgentApiProbeResult(
        ok: false,
        message: serverMessage.isEmpty
            ? 'Η απάντηση του API δεν ήταν επιτυχής.'
            : serverMessage,
      );
    } on SocketException catch (e) {
      return LansweeperAgentApiProbeResult(
        ok: false,
        message: 'Σφάλμα δικτύου: $e',
      );
    } on TimeoutException {
      return const LansweeperAgentApiProbeResult(
        ok: false,
        message: 'Timeout κατά την επικοινωνία με το Lansweeper API.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic>? _tryDecodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static bool _payloadSuccess(Map<String, dynamic>? payload) {
    if (payload == null) return false;
    final value = payload['Success'];
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    if (value is num) return value != 0;
    return false;
  }

  static String? _payloadMessage(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final value = payload['Message'];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String? _payloadTicketId(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final candidates = <Object?>[
      payload['TicketID'],
      payload['TicketId'],
      payload['Ticketid'],
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
