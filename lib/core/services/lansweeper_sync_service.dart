import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/calls/models/call_model.dart';
import 'lansweeper_ticket_requester_fields.dart';
import 'lansweeper_ticket_submit_config.dart';
import 'settings_service.dart';

typedef LansweeperRawPoster =
    Future<LansweeperRawResponse> Function(
      String action,
      Map<String, String> fields,
    );

class LansweeperRawResponse {
  const LansweeperRawResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class LansweeperSyncException implements Exception {
  const LansweeperSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Ρύθμιση/είσοδος αποτυχημένη πριν την κλήση API — δεν πρέπει να ενημερώνει κατάσταση κλήσης.
class LansweeperSyncPrecheckException implements Exception {
  const LansweeperSyncPrecheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LansweeperSyncRequest {
  const LansweeperSyncRequest({
    required this.call,
    required this.title,
    required this.notes,
    required this.solution,
    required this.agentUsername,
    this.durationSeconds,
  });

  final CallModel call;
  final String title;
  final String notes;
  final String solution;
  final String agentUsername;
  /// Συνολική διάρκεια (δευτερόλεπτα) για την αποστολή· αν λείπει, χρησιμοποιείται η διάρκεια της κλήσης.
  final int? durationSeconds;
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

class LansweeperWorkflowRequest {
  const LansweeperWorkflowRequest({
    required this.call,
    required this.title,
    required this.problem,
    required this.solution,
    required this.agentUsername,
    required this.config,
    required this.customFieldValues,
    this.durationSeconds,
    this.targetState,
    this.existingTicketId,
  });

  final CallModel call;
  final String title;
  final String problem;
  final String solution;
  final String agentUsername;
  final int? durationSeconds;
  final LansweeperTicketSubmitConfig config;
  final Map<String, String> customFieldValues;
  final String? targetState;
  final String? existingTicketId;
}

class LansweeperWorkflowResult {
  const LansweeperWorkflowResult({
    required this.success,
    required this.message,
    this.ticketId,
    this.completedSteps = const [],
    this.warnings = const [],
    this.failedStep,
    this.rawPayloads,
  });

  final bool success;
  final String? ticketId;
  final String message;
  final List<String> completedSteps;
  final List<String> warnings;
  final String? failedStep;
  final Map<String, dynamic>? rawPayloads;
}

class _PostActionResult {
  const _PostActionResult({
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
  factory LansweeperSyncService({
    SettingsService? settingsService,
    LansweeperRawPoster? poster,
  }) {
    final settings = settingsService ?? SettingsService();
    return LansweeperSyncService._(
      poster ?? _defaultPosterFor(settings),
    );
  }

  LansweeperSyncService._(this._poster);

  final LansweeperRawPoster _poster;

  static LansweeperRawPoster _defaultPosterFor(
    SettingsService settingsService,
  ) {
    return (action, fields) =>
        _defaultRawPoster(settingsService, action, fields);
  }

  Future<LansweeperSyncResult> submitAddTicket(
    LansweeperSyncRequest request,
  ) async {
    if (request.agentUsername.trim().isEmpty) {
      throw const LansweeperSyncPrecheckException(
        'Ο πράκτορας API (AgentUsername) είναι υποχρεωτικός.',
      );
    }

    final subject = request.title.trim().isNotEmpty
        ? request.title.trim()
        : _buildSubject(request.call);
    final description = _buildDescription(
      notes: request.notes,
      solution: request.solution,
      durationSeconds: request.durationSeconds ?? request.call.duration,
    );

    final form = <String, String>{
      'Subject': subject,
      'Description': description,
      ..._requesterFields(request.agentUsername),
    };

    final result = await _postAction('AddTicket', form);
    return LansweeperSyncResult(
      success: result.success,
      message: result.message,
      ticketId: result.ticketId,
      rawPayload: result.rawPayload,
    );
  }

  Future<LansweeperWorkflowResult> submitTicketWorkflow(
    LansweeperWorkflowRequest request,
  ) async {
    if (request.agentUsername.trim().isEmpty) {
      throw const LansweeperSyncPrecheckException(
        'Ο πράκτορας API (AgentUsername) είναι υποχρεωτικός.',
      );
    }

    final completedSteps = <String>[];
    final warnings = <String>[];
    final rawPayloads = <String, dynamic>{};
    final config = request.config;
    final durationSeconds = request.durationSeconds ?? request.call.duration;

    var ticketId = request.existingTicketId?.trim();
    if (ticketId != null && ticketId.isEmpty) {
      ticketId = null;
    }

    if (ticketId == null) {
      final fields = <String, String>{
        'Subject': request.title.trim().isNotEmpty
            ? request.title.trim()
            : _buildSubject(request.call),
        'Description': request.problem.trim(),
        if (config.ticketType.trim().isNotEmpty) 'Type': config.ticketType.trim(),
        if (config.priority.trim().isNotEmpty) 'Priority': config.priority.trim(),
        if (config.team.trim().isNotEmpty) 'Team': config.team.trim(),
        'CustomFields': _encodeCustomFields(
          config,
          request.customFieldValues,
        ),
        ..._requesterFields(request.agentUsername),
      };

      final addResult = await _postAction('AddTicket', fields);
      rawPayloads['AddTicket'] = addResult.rawPayload;

      if (!addResult.success) {
        return LansweeperWorkflowResult(
          success: false,
          message: addResult.message,
          completedSteps: completedSteps,
          warnings: warnings,
          failedStep: 'AddTicket',
          rawPayloads: rawPayloads,
        );
      }

      ticketId = addResult.ticketId;
      if (ticketId == null || ticketId.isEmpty) {
        return LansweeperWorkflowResult(
          success: false,
          message: addResult.message,
          completedSteps: completedSteps,
          warnings: warnings,
          failedStep: 'AddTicket',
          rawPayloads: rawPayloads,
        );
      }

      completedSteps.add('AddTicket');
    }

    final resolvedTicketId = ticketId;

    if (config.enableAddNoteStep && request.solution.trim().isNotEmpty) {
      final noteFields = <String, String>{
        'TicketID': resolvedTicketId,
        'Text': _buildNoteText(
          request.solution,
          durationSeconds,
          includeTime: config.includeNoteTime,
        ),
        'Type': config.noteType,
        ..._requesterFields(request.agentUsername),
      };

      final noteResult = await _postAction('AddNote', noteFields);
      rawPayloads['AddNote'] = noteResult.rawPayload;

      if (noteResult.success) {
        completedSteps.add('AddNote');
      } else {
        final fallbackFields = <String, String>{
          'TicketID': resolvedTicketId,
          'Description': buildTicketDescription(
            notes: request.problem,
            solution: request.solution,
            durationSeconds: durationSeconds,
          ),
          ..._requesterFields(request.agentUsername),
        };
        final fallbackResult = await _postAction('EditTicket', fallbackFields);
        rawPayloads['EditTicket(fallback)'] = fallbackResult.rawPayload;

        if (fallbackResult.success) {
          completedSteps.add('EditTicket(fallback)');
          warnings.add(
            'Η σημείωση απέτυχε· η λύση καταχωρήθηκε στην περιγραφή του ticket.',
          );
        } else {
          return LansweeperWorkflowResult(
            success: false,
            message: noteResult.message,
            ticketId: resolvedTicketId,
            completedSteps: completedSteps,
            warnings: warnings,
            failedStep: 'AddNote',
            rawPayloads: rawPayloads,
          );
        }
      }
    }

    final targetState = request.targetState?.trim() ?? '';
    if (config.enableStateUpdateStep && targetState.isNotEmpty) {
      final stateFields = <String, String>{
        'TicketID': resolvedTicketId,
        'State': targetState,
        ..._requesterFields(request.agentUsername),
      };

      final stateResult = await _postAction('EditTicket', stateFields);
      rawPayloads['EditTicket(state)'] = stateResult.rawPayload;

      if (stateResult.success) {
        completedSteps.add('EditTicket(state)');
      } else {
        return LansweeperWorkflowResult(
          success: false,
          message: stateResult.message,
          ticketId: resolvedTicketId,
          completedSteps: completedSteps,
          warnings: warnings,
          failedStep: 'EditTicket',
          rawPayloads: rawPayloads,
        );
      }
    }

    return LansweeperWorkflowResult(
      success: true,
      message: _workflowSuccessMessage(completedSteps),
      ticketId: resolvedTicketId,
      completedSteps: completedSteps,
      warnings: warnings,
      rawPayloads: rawPayloads,
    );
  }

  Future<_PostActionResult> _postAction(
    String action,
    Map<String, String> fields,
  ) async {
    try {
      final response = await _poster(action, fields);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LansweeperSyncException(
          'Αποτυχία API (${response.statusCode}): ${response.body}',
        );
      }

      final payload = _tryDecodeJson(response.body);
      final success = _payloadSuccess(payload);
      final message = _payloadMessage(payload) ?? 'Η απάντηση παραλήφθηκε.';
      final ticketId = _payloadTicketId(payload);

      return _PostActionResult(
        success: success,
        message: message,
        ticketId: ticketId,
        rawPayload: payload,
      );
    } on LansweeperSyncException {
      rethrow;
    } on SocketException catch (e) {
      throw LansweeperSyncException('Σφάλμα δικτύου: $e');
    } on TimeoutException {
      throw const LansweeperSyncException(
        'Timeout κατά την επικοινωνία με το Lansweeper API.',
      );
    }
  }

  static Future<LansweeperRawResponse> _defaultRawPoster(
    SettingsService settingsService,
    String action,
    Map<String, String> fields,
  ) async {
    final apiUrl = (await settingsService.getLansweeperApiUrl())?.trim() ?? '';
    final apiKey = (await settingsService.getLansweeperApiKey())?.trim() ?? '';
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
        'action': action,
        'key': apiKey,
      },
    );

    final client = HttpClient();
    try {
      final httpRequest = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      httpRequest.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      httpRequest.write(Uri(queryParameters: fields).query);
      final response = await httpRequest.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      return LansweeperRawResponse(response.statusCode, body);
    } finally {
      client.close(force: true);
    }
  }

  String _encodeCustomFields(
    LansweeperTicketSubmitConfig config,
    Map<String, String> values,
  ) {
    final customFields = <Map<String, String>>[];
    for (final field in config.customFields) {
      final value = values[field.id] ?? field.defaultValue;
      customFields.add({
        'name': field.apiName,
        'value': value,
      });
    }
    return jsonEncode({'customFields': customFields});
  }

  String _buildNoteText(
    String solution,
    int? durationSeconds, {
    required bool includeTime,
  }) {
    final text = solution.trim();
    if (!includeTime || durationSeconds == null) return text;
    return '$text\n\nΧρόνος: ${formatCallDurationLabel(durationSeconds)}';
  }

  Map<String, String> _requesterFields(String agentUsername) =>
      lansweeperAgentAsMatchingRequesterFields(agentUsername);

  String _workflowSuccessMessage(List<String> completedSteps) {
    if (completedSteps.isEmpty) {
      return 'Η ροή ολοκληρώθηκε.';
    }
    return 'Ολοκληρώθηκαν: ${completedSteps.join(', ')}.';
  }

  String _buildSubject(CallModel call) {
    final category = (call.category ?? '').trim();
    final id = call.id;
    final suffix = id != null ? ' #$id' : '';
    if (category.isEmpty) {
      return id != null ? 'Κλήση$suffix' : 'Κλήση';
    }
    return '[$category]$suffix';
  }

  static String formatCallDurationLabel(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    final s = safe % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String buildTicketDescription({
    required String notes,
    required String solution,
    int? durationSeconds,
  }) {
    final notesTrim = notes.trim();
    final solutionTrim = solution.trim();
    final String body;
    if (solutionTrim.isEmpty) {
      body = notesTrim;
    } else if (notesTrim.isEmpty) {
      body = 'Λύση:\n$solutionTrim';
    } else {
      body = '$notesTrim\n\nΛύση:\n$solutionTrim';
    }
    if (durationSeconds == null) return body;
    final durationLine =
        'Χρόνος: ${formatCallDurationLabel(durationSeconds)}';
    if (body.isEmpty) return durationLine;
    return '$body\n\n$durationLine';
  }

  String _buildDescription({
    required String notes,
    required String solution,
    int? durationSeconds,
  }) =>
      buildTicketDescription(
        notes: notes,
        solution: solution,
        durationSeconds: durationSeconds,
      );

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
