import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/calls/models/call_model.dart';
import 'lansweeper_asset_target.dart';
import 'lansweeper_ticket_requester_fields.dart';
import 'lansweeper_ticket_submit_config.dart';
import 'settings_service.dart';

typedef LansweeperRawPoster =
    Future<LansweeperRawResponse> Function(
      String action,
      Map<String, String> fields,
    );

/// GET προς το API (π.χ. `SearchUsers`) — οι παράμετροι μπαίνουν στο URL.
typedef LansweeperRawGetter =
    Future<LansweeperRawResponse> Function(
      String action,
      Map<String, String> params,
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
    this.requesterUsername,
    this.assetTarget,
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

  /// Ταυτότητα Lansweeper του υπαλλήλου που κάλεσε (`τομέας\όνομα` ή email).
  /// Κενή/null = ο αιτών μένει ο πράκτορας, όπως πριν.
  final String? requesterUsername;

  /// Στόχος `AddAsset` για τον εξοπλισμό της κλήσης. Null = χωρίς σύνδεση.
  final LansweeperAssetTarget? assetTarget;
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
    LansweeperRawGetter? getter,
  }) {
    final settings = settingsService ?? SettingsService();
    return LansweeperSyncService._(
      poster ?? _defaultPosterFor(settings),
      getter ?? _defaultGetterFor(settings),
    );
  }

  LansweeperSyncService._(this._poster, this._getter);

  final LansweeperRawPoster _poster;
  final LansweeperRawGetter _getter;

  static LansweeperRawPoster _defaultPosterFor(
    SettingsService settingsService,
  ) {
    return (action, fields) =>
        _defaultRawPoster(settingsService, action, fields);
  }

  static LansweeperRawGetter _defaultGetterFor(
    SettingsService settingsService,
  ) {
    return (action, params) =>
        _defaultRawGetter(settingsService, action, params);
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

    // Ο αιτών του εισιτηρίου. Ξεκινά ως ο πράκτορας (σημερινή συμπεριφορά)
    // και γίνεται ο υπάλληλος ΜΟΝΟ αν το SearchUsers τον επιβεβαιώσει: άγνωστο
    // email στο AddTicket δεν αποτυγχάνει — δημιουργεί σιωπηλά ψευτο-χρήστη
    // στο helpdesk, ενώ άγνωστο όνομα χαλά ολόκληρη τη δημιουργία.
    final agent = request.agentUsername.trim();
    var requester = agent;
    final candidateRequester = request.requesterUsername?.trim() ?? '';
    if (candidateRequester.isNotEmpty) {
      if (await _requesterExistsInLansweeper(candidateRequester)) {
        requester = candidateRequester;
      } else {
        warnings.add(
          'Ο αιτών «$candidateRequester» δεν βρέθηκε στο Lansweeper· '
          'αιτών καταχωρήθηκε ο πράκτορας.',
        );
      }
    }

    var ticketId = request.existingTicketId?.trim();
    if (ticketId != null && ticketId.isEmpty) {
      ticketId = null;
    }

    if (ticketId == null) {
      final baseFields = <String, String>{
        'Subject': request.title.trim().isNotEmpty
            ? request.title.trim()
            : _buildSubject(request.call),
        'Description': request.problem.trim(),
        if (config.ticketType.trim().isNotEmpty)
          'Type': config.ticketType.trim(),
        if (config.priority.trim().isNotEmpty)
          'Priority': config.priority.trim(),
        if (config.team.trim().isNotEmpty) 'Team': config.team.trim(),
        'CustomFields': _encodeCustomFields(config, request.customFieldValues),
      };

      var addResult = await _postAction('AddTicket', <String, String>{
        ...baseFields,
        ..._ticketIdentityFields(requester, agent),
      });
      rawPayloads['AddTicket'] = addResult.rawPayload;

      if (!addResult.success && requester != agent) {
        // Δεύτερο δίχτυ: ο προ-έλεγχος ταιριάζει και μερικώς (substring), άρα
        // μια ταυτότητα μπορεί να «βρεθεί» χωρίς να αντιστοιχεί ακριβώς σε
        // χρήστη. Το αίτημα δεν χάνεται — ξαναστέλνεται όπως πριν.
        warnings.add(
          'Η δημιουργία με αιτούντα «$requester» απέτυχε· '
          'αιτών καταχωρήθηκε ο πράκτορας.',
        );
        requester = agent;
        addResult = await _postAction('AddTicket', <String, String>{
          ...baseFields,
          ..._ticketIdentityFields(requester, agent),
        });
        rawPayloads['AddTicket(retry)'] = addResult.rawPayload;
      }

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

      final assetTarget = request.assetTarget;
      if (assetTarget != null) {
        await _attachAssetStep(
          ticketId: ticketId,
          target: assetTarget,
          completedSteps: completedSteps,
          warnings: warnings,
          rawPayloads: rawPayloads,
        );
      }
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
        // Στο EditTicket το Username ΑΛΛΑΖΕΙ τον αιτούντα του εισιτηρίου —
        // κάθε βήμα μετά τη δημιουργία κουβαλά τον ίδιο αιτούντα, αλλιώς το
        // κλείσιμο θα τον ξαναγύριζε σιωπηλά στον πράκτορα.
        final fallbackFields = <String, String>{
          'TicketID': resolvedTicketId,
          'Description': buildTicketDescription(
            notes: request.problem,
            solution: request.solution,
            durationSeconds: durationSeconds,
          ),
          ..._ticketIdentityFields(requester, agent),
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
        ..._ticketIdentityFields(requester, agent),
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

  /// Σύνδεση εξοπλισμού στο νεοδημιουργημένο ticket. Αποτυχία = προειδοποίηση,
  /// ποτέ αποτυχία ροής: το εισιτήριο υπάρχει ήδη και είναι σωστό.
  Future<void> _attachAssetStep({
    required String ticketId,
    required LansweeperAssetTarget target,
    required List<String> completedSteps,
    required List<String> warnings,
    required Map<String, dynamic> rawPayloads,
  }) async {
    final fields = <String, String>{
      'TicketID': ticketId,
      if (target.kind == LansweeperAssetTargetKind.ipAddress)
        'IPAddress': target.value
      else
        'AssetName': target.value,
    };
    try {
      final result = await _postAction('AddAsset', fields);
      rawPayloads['AddAsset'] = result.rawPayload;
      if (result.success) {
        completedSteps.add('AddAsset');
      } else {
        warnings.add(
          'Ο εξοπλισμός «${target.value}» δεν συνδέθηκε στο αίτημα: '
          '${result.message}',
        );
      }
    } on LansweeperSyncException catch (e) {
      warnings.add(
        'Ο εξοπλισμός «${target.value}» δεν συνδέθηκε στο αίτημα: '
        '${e.message}',
      );
    }
  }

  /// Πεδία ταυτότητας για AddTicket/EditTicket: όταν αιτών == πράκτορας, η
  /// σημερινή μορφή (ίδια τιμή παντού)· αλλιώς αιτών και πράκτορας χωριστά.
  Map<String, String> _ticketIdentityFields(String requester, String agent) {
    if (requester == agent) {
      return lansweeperAgentAsMatchingRequesterFields(agent);
    }
    return lansweeperRequesterAndAgentFields(requester: requester, agent: agent);
  }

  /// Προ-έλεγχος `SearchUsers`: υπάρχει ο χρήστης στο Lansweeper;
  ///
  /// Κάθε αμφιβολία (σφάλμα δικτύου, μη-JSON, Count=0) μετρά ως «όχι» — το
  /// κόστος του λάθους είναι ασύμμετρο: άγνωστο email θα δημιουργούσε
  /// ψευτο-χρήστη, άγνωστο όνομα θα χαλούσε τη δημιουργία του ticket.
  Future<bool> _requesterExistsInLansweeper(String identity) async {
    try {
      final response = await _getter(
        'SearchUsers',
        lansweeperSearchUsersParamsFor(identity),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final payload = _tryDecodeJson(response.body);
      if (!_payloadSuccess(payload)) return false;
      final count = payload?['Count'];
      if (count is num) return count > 0;
      if (count is String) return (int.tryParse(count.trim()) ?? 0) > 0;
      return false;
    } on Exception {
      return false;
    }
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

  /// URL του API για το [action], με το κλειδί και τυχόν [extraQueryParams].
  static Future<Uri> _apiActionUri(
    SettingsService settingsService,
    String action, {
    Map<String, String> extraQueryParams = const {},
  }) async {
    final apiUrl =
        (await settingsService.remoteLansweeper.getLansweeperApiUrl())
            ?.trim() ??
        '';
    final apiKey =
        (await settingsService.remoteLansweeper.getLansweeperApiKey())
            ?.trim() ??
        '';
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

    return baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        'action': action,
        'key': apiKey,
        ...extraQueryParams,
      },
    );
  }

  static Future<LansweeperRawResponse> _defaultRawPoster(
    SettingsService settingsService,
    String action,
    Map<String, String> fields,
  ) async {
    final uri = await _apiActionUri(settingsService, action);

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

  /// GET για ενέργειες ανάγνωσης (`SearchUsers`) — παράμετροι στο URL.
  static Future<LansweeperRawResponse> _defaultRawGetter(
    SettingsService settingsService,
    String action,
    Map<String, String> params,
  ) async {
    final uri = await _apiActionUri(
      settingsService,
      action,
      extraQueryParams: params,
    );

    final client = HttpClient();
    try {
      final httpRequest = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
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
      customFields.add({'name': field.apiName, 'value': value});
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
    final durationLine = 'Χρόνος: ${formatCallDurationLabel(durationSeconds)}';
    if (body.isEmpty) return durationLine;
    return '$body\n\n$durationLine';
  }

  String _buildDescription({
    required String notes,
    required String solution,
    int? durationSeconds,
  }) => buildTicketDescription(
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
