import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/calls/models/call_model.dart';
import 'settings_service.dart';

class LansweeperSyncException implements Exception {
  const LansweeperSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LansweeperSyncRequest {
  const LansweeperSyncRequest({
    required this.call,
    required this.title,
    required this.notes,
    required this.agentUsername,
  });

  final CallModel call;
  final String title;
  final String notes;
  final String agentUsername;
}

class LansweeperSyncResult {
  const LansweeperSyncResult({
    required this.success,
    required this.message,
    this.ticketId,
    this.rawPayload,
  });

  final bool success;
  final String message;
  final String? ticketId;
  final Map<String, dynamic>? rawPayload;
}

class LansweeperSyncService {
  LansweeperSyncService({SettingsService? settingsService})
    : _settingsService = settingsService ?? SettingsService();

  final SettingsService _settingsService;

  Future<LansweeperSyncResult> submitAddTicket(
    LansweeperSyncRequest request,
  ) async {
    final apiUrl = (await _settingsService.getLansweeperApiUrl())?.trim() ?? '';
    final apiKey = (await _settingsService.getLansweeperApiKey())?.trim() ?? '';
    if (apiUrl.isEmpty) {
      throw const LansweeperSyncException(
        'Δεν έχει οριστεί Lansweeper API URL.',
      );
    }
    if (apiKey.isEmpty) {
      throw const LansweeperSyncException(
        'Δεν έχει οριστεί Lansweeper API key.',
      );
    }

    final baseUri = Uri.tryParse(apiUrl);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      throw LansweeperSyncException('Μη έγκυρο Lansweeper API URL: $apiUrl');
    }

    final uri = baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        'action': 'AddTicket',
        'key': apiKey,
      },
    );

    final subject = request.title.trim().isNotEmpty
        ? request.title.trim()
        : _buildSubject(request.call);
    final description = _buildDescription(
      call: request.call,
      notes: request.notes,
    );

    final form = <String, String>{
      'Subject': subject,
      'Description': description,
      'Displayname': _callerLabel(request.call),
    };
    final agent = request.agentUsername.trim();
    if (agent.isNotEmpty) {
      form['AgentUsername'] = agent;
    }

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
        throw LansweeperSyncException(
          'Αποτυχία API (${response.statusCode}): $body',
        );
      }

      final payload = _tryDecodeJson(body);
      final success = _payloadSuccess(payload);
      final message = _payloadMessage(payload) ?? 'Η απάντηση παραλήφθηκε.';
      final ticketId = _payloadTicketId(payload);

      return LansweeperSyncResult(
        success: success,
        message: message,
        ticketId: ticketId,
        rawPayload: payload,
      );
    } on SocketException catch (e) {
      throw LansweeperSyncException('Σφάλμα δικτύου: $e');
    } on TimeoutException {
      throw const LansweeperSyncException(
        'Timeout κατά την επικοινωνία με το Lansweeper API.',
      );
    } finally {
      client.close(force: true);
    }
  }

  String _buildSubject(CallModel call) {
    final category = (call.category ?? '').trim();
    final caller = _callerLabel(call);
    if (category.isEmpty) return caller;
    return '[$category] $caller';
  }

  String _buildDescription({required CallModel call, required String notes}) {
    final parts = <String>[];
    final trimmedNotes = notes.trim();
    if (trimmedNotes.isNotEmpty) {
      parts.add(trimmedNotes);
    }
    final issue = (call.issue ?? '').trim();
    if (issue.isNotEmpty) {
      parts.add('Issue: $issue');
    }
    final solution = (call.solution ?? '').trim();
    if (solution.isNotEmpty) {
      parts.add('Solution: $solution');
    }
    final department = (call.departmentText ?? '').trim();
    if (department.isNotEmpty) {
      parts.add('Department: $department');
    }
    final equipment = (call.equipmentText ?? '').trim();
    if (equipment.isNotEmpty) {
      parts.add('Equipment: $equipment');
    }
    final callId = call.id;
    if (callId != null) {
      parts.add('Call ID: $callId');
    }
    return parts.join('\n');
  }

  String _callerLabel(CallModel call) {
    final value = (call.callerText ?? '').trim();
    return value.isEmpty ? 'Unknown caller' : value;
  }

  Map<String, dynamic>? _tryDecodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  bool _payloadSuccess(Map<String, dynamic>? payload) {
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

  String? _payloadMessage(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final value = payload['Message'];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? _payloadTicketId(Map<String, dynamic>? payload) {
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
