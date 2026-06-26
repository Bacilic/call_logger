import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gemini_prompt_template_syntax.dart';

export 'gemini_prompt_template_syntax.dart'
    show
        GeminiPromptPlaceholder,
        GeminiPromptTemplateSyntax,
        GeminiPromptTemplateValidation,
        GeminiPromptTokenKind,
        GeminiPromptTokenSpan,
        kGeminiPromptPlaceholders;

const String kGeminiPrimaryModelPlaceholder = '{προτεύων μοντέλο}';
const String kGeminiApiKeyPlaceholder = '{κλειδί API}';

const String kDefaultGeminiPrimaryModel = 'gemini-flash-latest';

const String kDefaultGeminiEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/models/$kGeminiPrimaryModelPlaceholder:generateContent?key=$kGeminiApiKeyPlaceholder';

/// Προεπιλεγμένο εφεδρικό μοντέλο (fallback) σε περίπτωση 503.
const String kDefaultGeminiFallbackModel = 'gemini-2.5-flash-lite';

const String kGeminiModelsListUrl =
    'https://generativelanguage.googleapis.com/v1beta/models';

/// Μοντέλο κειμένου Gemini από τη λίστα API.
class GeminiTextModel {
  const GeminiTextModel({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

/// Αποτέλεσμα δοκιμαστικής κλήσης μοντέλου.
class GeminiModelProbeResult {
  const GeminiModelProbeResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

/// Προειδοποίηση για πληκτρολογημένο κύριο/εφεδρικό μοντέλο χωρίς ποσόστωση.
class GeminiTypedModelQuotaWarning {
  const GeminiTypedModelQuotaWarning({
    required this.modelId,
    required this.slotLabel,
    required this.message,
  });

  final String modelId;
  final String slotLabel;
  final String message;
}

/// Αποτέλεσμα μαζικού ελέγχου ποσόστωσης μοντέλων.
class GeminiModelsQuotaProbeResult {
  const GeminiModelsQuotaProbeResult({
    required this.availableModels,
    required this.totalChecked,
    required this.message,
    this.typedModelWarnings = const [],
  });

  final List<GeminiTextModel> availableModels;
  final int totalChecked;
  final String message;
  final List<GeminiTypedModelQuotaWarning> typedModelWarnings;
}

/// Αποθηκευμένο αποτέλεσμα μαζικού ελέγχου ποσόστωσης μοντέλων.
class GeminiModelsProbeCache {
  const GeminiModelsProbeCache({
    required this.checkedAt,
    required this.result,
  });

  final DateTime checkedAt;
  final GeminiModelsQuotaProbeResult result;

  static GeminiModelsProbeCache? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final checkedAtRaw = decoded['checkedAt']?.toString();
      if (checkedAtRaw == null || checkedAtRaw.isEmpty) return null;
      final checkedAt = DateTime.tryParse(checkedAtRaw);
      if (checkedAt == null) return null;

      final modelsRaw = decoded['availableModels'];
      final models = <GeminiTextModel>[];
      if (modelsRaw is List) {
        for (final item in modelsRaw) {
          if (item is! Map) continue;
          final id = item['id']?.toString().trim() ?? '';
          if (id.isEmpty) continue;
          models.add(
            GeminiTextModel(
              id: id,
              displayName: (item['displayName'] as String? ?? id).trim(),
            ),
          );
        }
      }

      final totalChecked = decoded['totalChecked'];
      final message = decoded['message']?.toString().trim() ?? '';
      final warnings = <GeminiTypedModelQuotaWarning>[];
      final warningsRaw = decoded['typedModelWarnings'];
      if (warningsRaw is List) {
        for (final item in warningsRaw) {
          if (item is! Map) continue;
          final modelId = item['modelId']?.toString().trim() ?? '';
          final slotLabel = item['slotLabel']?.toString().trim() ?? '';
          final warningMessage = item['message']?.toString().trim() ?? '';
          if (modelId.isEmpty) continue;
          warnings.add(
            GeminiTypedModelQuotaWarning(
              modelId: modelId,
              slotLabel: slotLabel.isEmpty ? 'μοντέλο' : slotLabel,
              message: warningMessage.isEmpty
                  ? 'Το μοντέλο «$modelId» δεν έχει διαθέσιμη ποσόστωση (> 0).'
                  : warningMessage,
            ),
          );
        }
      }

      return GeminiModelsProbeCache(
        checkedAt: checkedAt.toLocal(),
        result: GeminiModelsQuotaProbeResult(
          availableModels: models,
          totalChecked: totalChecked is int
              ? totalChecked
              : int.tryParse(totalChecked?.toString() ?? '') ?? models.length,
          message: message.isEmpty
              ? '${models.length} διαθέσιμα μοντέλα κειμένου.'
              : message,
          typedModelWarnings: warnings,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  String encode() {
    return jsonEncode(<String, dynamic>{
      'checkedAt': checkedAt.toUtc().toIso8601String(),
      'totalChecked': result.totalChecked,
      'message': result.message,
      'availableModels': [
        for (final model in result.availableModels)
          <String, String>{
            'id': model.id,
            'displayName': model.displayName,
          },
      ],
      'typedModelWarnings': [
        for (final warning in result.typedModelWarnings)
          <String, String>{
            'modelId': warning.modelId,
            'slotLabel': warning.slotLabel,
            'message': warning.message,
          },
      ],
    });
  }
}

/// Εξαίρεση κλήσης Gemini με προαιρετικό κωδικό κατάστασης HTTP.
class GeminiException implements Exception {
  const GeminiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

const String kDefaultGeminiPromptTemplate = '''Δημιούργησε τίτλο και πλήρη περιγραφή για ticket helpdesk στο Lansweeper.

Υπάλληλος: {Υπάλληλος}. Τμήμα: {Τμήμα}.
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}. {@/Εξοπλισμός}
{@Κατηγορία}Κατηγορία: {Κατηγορία}. {@/Κατηγορία}

Πρόβλημα: {Πρόβλημα}
{@Λύση}Λύση (προσχέδιο): {Λύση}. {@/Λύση}

Τρέχον προσχέδιο τίτλου: {Τίτλος}
Τρέχουσα περιγραφή: {Σημειώσεις}

Βελτίωσε το προσχέδιο με βάση τα στοιχεία κλήσης.
Η περιγραφή (description) να περιέχει ΜΟΝΟ το πρόβλημα/αιτιολόγηση.
Η λύση/αντιμετώπιση να μπει στο πεδίο solution, όχι στην description.
Απάντησε ΜΟΝΟ σε JSON χωρίς markdown: {"title":"...","description":"...","solution":"..."}''';

abstract final class GeminiTicketService {

  static String buildPrompt({
    required String promptTemplate,
    required String callerText,
    required String equipmentText,
    required String departmentText,
    required String category,
    required String issue,
    required String titleText,
    required String notesText,
    required String solutionText,
  }) {
    final trimmedNotes = notesText.trim();
    final trimmedIssue = issue.trim();
    final problemText = trimmedNotes.isNotEmpty
        ? trimmedNotes
        : trimmedIssue.trim();
    final values = <String, String>{
      '{Υπάλληλος}': callerText.trim(),
      '{Εξοπλισμός}': equipmentText.trim(),
      '{Τμήμα}': departmentText.trim(),
      '{Κατηγορία}': category.trim(),
      '{Τίτλος}': titleText.trim(),
      '{Σημειώσεις}': trimmedNotes,
      '{Πρόβλημα}': problemText,
      '{Λύση}': solutionText.trim(),
    };

    final emptyTokens = <String>{
      for (final entry in values.entries)
        if (entry.value.isEmpty) entry.key,
    };

    var prompt = promptTemplate.trim().isEmpty
        ? kDefaultGeminiPromptTemplate
        : promptTemplate;
    prompt = GeminiPromptTemplateSyntax.stripEmptyOptionalBlocks(
      prompt,
      emptyTokens,
    );
    for (final entry in values.entries) {
      prompt = prompt.replaceAll(entry.key, entry.value);
    }
    prompt = GeminiPromptTemplateSyntax.stripBlockMarkers(prompt);
    return GeminiPromptTemplateSyntax.compactWhitespace(prompt);
  }

  /// Κανονικοποιεί παλιά endpoints (`{apiKey}`, σταθερό μοντέλο) στο πρότυπο placeholders.
  static String normalizeEndpointTemplate(String endpoint) {
    var template = endpoint.trim().isEmpty ? kDefaultGeminiEndpoint : endpoint.trim();
    template = template.replaceAll('{apiKey}', kGeminiApiKeyPlaceholder);
    final match = _modelPattern.firstMatch(template);
    if (match != null) {
      final modelId = match.group(1)?.trim() ?? '';
      if (modelId.isNotEmpty &&
          modelId != kGeminiPrimaryModelPlaceholder &&
          !template.contains(kGeminiPrimaryModelPlaceholder)) {
        template = template.replaceFirst(_modelPattern, 'models/$kGeminiPrimaryModelPlaceholder');
      }
    }
    return template;
  }

  static String resolveEndpoint({
    required String endpoint,
    required String apiKey,
    String? primaryModel,
  }) {
    var template = normalizeEndpointTemplate(endpoint);
    final model = (primaryModel ?? kDefaultGeminiPrimaryModel).trim();
    if (model.isNotEmpty && template.contains(kGeminiPrimaryModelPlaceholder)) {
      template = template.replaceAll(kGeminiPrimaryModelPlaceholder, model);
    }
    return template.replaceAll(kGeminiApiKeyPlaceholder, apiKey.trim());
  }

  static final RegExp _modelPattern = RegExp(r'models/([^:/?]+)');

  /// Εξάγει σταθερό όνομα μοντέλου από παλιό endpoint (όχι placeholder).
  static String? modelFromEndpoint(String endpoint) {
    final trimmed = endpoint.trim();
    if (trimmed.contains(kGeminiPrimaryModelPlaceholder)) return null;
    final match = _modelPattern.firstMatch(trimmed);
    return match?.group(1);
  }

  /// Επιστρέφει template endpoint με αντικατεστημένο μοντέλο (για εφεδρικό).
  static String endpointWithModel(String endpoint, String model) {
    final source = normalizeEndpointTemplate(endpoint);
    final target = model.trim();
    if (target.isEmpty) return source;
    if (source.contains(kGeminiPrimaryModelPlaceholder)) {
      return source.replaceAll(kGeminiPrimaryModelPlaceholder, target);
    }
    if (_modelPattern.hasMatch(source)) {
      return source.replaceFirst(_modelPattern, 'models/$target');
    }
    return source;
  }

  static final RegExp _nonTextModelPattern = RegExp(
    r'image|tts|veo|imagen|lyria|embed|robotics|computer-use|'
    r'deep-research|antigravity|nano-banana|aqa',
    caseSensitive: false,
  );

  static bool _isTextGenerationModel(Map<String, dynamic> raw) {
    final methods = raw['supportedGenerationMethods'];
    if (methods is! List || !methods.contains('generateContent')) {
      return false;
    }
    final name = (raw['name'] as String? ?? '').toLowerCase();
    if (!name.startsWith('models/')) return false;
    if (_nonTextModelPattern.hasMatch(name)) return false;
    return true;
  }

  static String _modelIdFromApiName(String apiName) {
    return apiName.startsWith('models/')
        ? apiName.substring('models/'.length)
        : apiName;
  }

  /// Λίστα μοντέλων κειμένου (`generateContent`) από το Gemini API.
  static Future<List<GeminiTextModel>> listTextModels({
    required String apiKey,
    http.Client? client,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const GeminiException('Δεν έχει οριστεί Gemini API key.');
    }

    final httpClient = client ?? http.Client();
    final results = <GeminiTextModel>[];
    var pageToken = '';

    try {
      do {
        final uri = Uri.parse(kGeminiModelsListUrl).replace(
          queryParameters: <String, String>{
            'key': key,
            if (pageToken.isNotEmpty) 'pageToken': pageToken,
          },
        );
        final response = await httpClient
            .get(uri)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final apiMessage = _extractApiErrorMessage(response.body);
          throw GeminiException(
            apiMessage == null
                ? 'Αποτυχία HTTP (${response.statusCode}) κατά τη λίστα μοντέλων.'
                : 'Αποτυχία λίστας μοντέλων (${response.statusCode}): $apiMessage',
            statusCode: response.statusCode,
          );
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const GeminiException('Μη έγκυρη απάντηση λίστας μοντέλων.');
        }
        final models = decoded['models'];
        if (models is List) {
          for (final item in models) {
            if (item is! Map) continue;
            final raw = Map<String, dynamic>.from(item);
            if (!_isTextGenerationModel(raw)) continue;
            final id = _modelIdFromApiName(raw['name']?.toString() ?? '');
            if (id.isEmpty) continue;
            final displayName =
                (raw['displayName'] as String? ?? id).trim();
            results.add(GeminiTextModel(id: id, displayName: displayName));
          }
        }
        pageToken = (decoded['nextPageToken'] as String? ?? '').trim();
      } while (pageToken.isNotEmpty);
    } finally {
      if (client == null) httpClient.close();
    }

    results.sort((a, b) => a.id.compareTo(b.id));
    return results;
  }

  /// Μαζικός έλεγχος όλων των μοντέλων κειμένου· επιστρέφει μόνο όσα έχουν ποσόστωση > 0.
  static Future<GeminiModelsQuotaProbeResult> probeModelsWithQuota({
    required String apiKey,
    String endpointTemplate = kDefaultGeminiEndpoint,
    String? typedPrimaryModel,
    String? typedFallbackModel,
    bool checkTypedFallback = true,
    void Function(int current, int total, String modelId)? onProgress,
    http.Client? client,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const GeminiModelsQuotaProbeResult(
        availableModels: [],
        totalChecked: 0,
        message: 'Συμπληρώστε πρώτα το Gemini API key.',
      );
    }

    final httpClient = client ?? http.Client();
    try {
      final models = await listTextModels(apiKey: key, client: httpClient);
      if (models.isEmpty) {
        return const GeminiModelsQuotaProbeResult(
          availableModels: [],
          totalChecked: 0,
          message: 'Δεν βρέθηκαν μοντέλα κειμένου.',
        );
      }

      final modelById = {for (final model in models) model.id: model};
      final typedEntries = <({String id, String slot})>[];
      final primary = typedPrimaryModel?.trim() ?? '';
      final fallback = typedFallbackModel?.trim() ?? '';
      if (primary.isNotEmpty) {
        typedEntries.add((id: primary, slot: 'κύριο'));
      }
      if (checkTypedFallback &&
          fallback.isNotEmpty &&
          fallback != primary) {
        typedEntries.add((id: fallback, slot: 'εφεδρικό'));
      }
      final extrasToProbe = typedEntries
          .where((entry) => !modelById.containsKey(entry.id))
          .length;

      final available = <GeminiTextModel>[];
      final probeOkById = <String, bool>{};
      var checked = 0;
      final totalSteps = models.length + extrasToProbe;

      for (var i = 0; i < models.length; i++) {
        final model = models[i];
        checked++;
        onProgress?.call(checked, totalSteps, model.id);
        final result = await probeModel(
          apiKey: key,
          model: model.id,
          endpointTemplate: endpointTemplate,
          client: httpClient,
        );
        probeOkById[model.id] = result.ok;
        if (result.ok) available.add(model);
      }

      final warnings = <GeminiTypedModelQuotaWarning>[];

      for (final entry in typedEntries) {
        var ok = probeOkById[entry.id];
        String failureMessage =
            'Το πληκτρολογημένο ${entry.slot} μοντέλο «${entry.id}» '
            'δεν έχει διαθέσιμη ποσόστωση (> 0).';

        if (ok == null) {
          checked++;
          onProgress?.call(checked, totalSteps, entry.id);
          final result = await probeModel(
            apiKey: key,
            model: entry.id,
            endpointTemplate: endpointTemplate,
            client: httpClient,
          );
          ok = result.ok;
          probeOkById[entry.id] = ok;
          if (!ok) failureMessage = result.message;
        }

        if (ok == true) {
          if (!available.any((model) => model.id == entry.id)) {
            available.add(
              modelById[entry.id] ??
                  GeminiTextModel(id: entry.id, displayName: entry.id),
            );
          }
        } else {
          warnings.add(
            GeminiTypedModelQuotaWarning(
              modelId: entry.id,
              slotLabel: entry.slot,
              message: '$failureMessage Μπορείτε να το κρατήσετε.',
            ),
          );
        }
      }

      available.sort((a, b) => a.id.compareTo(b.id));

      return GeminiModelsQuotaProbeResult(
        availableModels: available,
        totalChecked: checked,
        typedModelWarnings: warnings,
        message: available.isEmpty
            ? 'Κανένα από τα ${models.length} μοντέλα δεν έχει διαθέσιμη ποσόστωση στο δωρεάν επίπεδο.'
            : '${available.length} από ${models.length} μοντέλα με διαθέσιμη ποσόστωση (> 0).',
      );
    } on GeminiException catch (e) {
      return GeminiModelsQuotaProbeResult(
        availableModels: [],
        totalChecked: 0,
        message: e.message,
      );
    } catch (e) {
      return GeminiModelsQuotaProbeResult(
        availableModels: [],
        totalChecked: 0,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Δοκιμαστική κλήση ελάχιστου αιτήματος για έλεγχο διαθεσιμότητας μοντέλου.
  static Future<GeminiModelProbeResult> probeModel({
    required String apiKey,
    required String model,
    String endpointTemplate = kDefaultGeminiEndpoint,
    http.Client? client,
  }) async {
    final modelId = model.trim();
    if (modelId.isEmpty) {
      return const GeminiModelProbeResult(
        ok: false,
        message: 'Συμπληρώστε όνομα μοντέλου.',
      );
    }

    try {
      await suggest(
        apiKey: apiKey,
        endpoint: endpointWithModel(endpointTemplate, modelId),
        promptTemplate:
            'Απάντησε ΜΟΝΟ σε JSON: {"title":"OK","description":"OK","solution":"OK"}',
        callerText: 'δοκιμή',
        equipmentText: '-',
        departmentText: '-',
        category: '-',
        issue: 'δοκιμή',
        titleText: 'δοκιμή',
        notesText: 'δοκιμή',
        solutionText: '-',
        client: client,
      );
      return GeminiModelProbeResult(
        ok: true,
        message: 'Το μοντέλο «$modelId» απάντησε επιτυχώς.',
      );
    } on GeminiException catch (e) {
      final status = e.statusCode;
      if (status == 429 && e.message.contains('limit: 0')) {
        return GeminiModelProbeResult(
          ok: false,
          message:
              'Το μοντέλο «$modelId» δεν είναι διαθέσιμο στο δωρεάν επίπεδο '
              '(ποσόστωση 0). Επιλέξτε άλλο μοντέλο.',
        );
      }
      return GeminiModelProbeResult(ok: false, message: e.message);
    } catch (e) {
      return GeminiModelProbeResult(
        ok: false,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  static Future<({String title, String description, String solution})> suggest({
    required String apiKey,
    required String endpoint,
    required String promptTemplate,
    required String callerText,
    required String equipmentText,
    required String departmentText,
    required String category,
    required String issue,
    required String titleText,
    required String notesText,
    required String solutionText,
    http.Client? client,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const GeminiException('Δεν έχει οριστεί Gemini API key.');
    }

    final resolvedEndpoint = resolveEndpoint(
      endpoint: endpoint,
      apiKey: key,
      primaryModel: modelFromEndpoint(endpoint),
    );
    final uri = Uri.tryParse(resolvedEndpoint);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const GeminiException('Μη έγκυρο URL endpoint Gemini.');
    }

    final prompt = buildPrompt(
      promptTemplate: promptTemplate,
      callerText: callerText,
      equipmentText: equipmentText,
      departmentText: departmentText,
      category: category,
      issue: issue,
      titleText: titleText,
      notesText: notesText,
      solutionText: solutionText,
    );

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

    final parsed = parseSuggestionJson(text);
    if (parsed == null) {
      throw const GeminiException('Μη έγκυρη μορφή JSON στην απάντηση Gemini.');
    }

    final normalized = normalizeSuggestionFields(
      description: parsed.description,
      solution: parsed.solution,
    );

    return (
      title: parsed.title.trim(),
      description: normalized.description,
      solution: normalized.solution,
    );
  }

  /// Αν η περιγραφή περιέχει ενσωματωμένη «Λύση:» (παλιά προτροπή), τη χωρίζει.
  static ({String description, String solution}) normalizeSuggestionFields({
    required String description,
    required String solution,
  }) {
    final solutionTrim = solution.trim();
    if (solutionTrim.isNotEmpty) {
      return (description: description.trim(), solution: solutionTrim);
    }
    final desc = description.trim();
    final match = RegExp(
      r'(?:\n\n|\n)Λύση:\s*',
      caseSensitive: false,
    ).firstMatch(desc);
    if (match == null) {
      return (description: desc, solution: '');
    }
    final problem = desc.substring(0, match.start).trim();
    final embedded = desc.substring(match.end).trim();
    return (description: problem, solution: embedded);
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

  static ({String title, String description, String solution})? parseSuggestionJson(
    String text,
  ) {
    try {
      var payload = text.trim();
      if (payload.startsWith('```')) {
        payload = payload
            .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
            .replaceFirst(RegExp(r'\s*```$'), '');
      }
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final title = decoded['title']?.toString().trim() ?? '';
      final description = decoded['description']?.toString().trim() ?? '';
      final solution = decoded['solution']?.toString().trim() ?? '';
      if (title.isEmpty && description.isEmpty && solution.isEmpty) {
        return null;
      }
      return (title: title, description: description, solution: solution);
    } catch (_) {
      return null;
    }
  }
}
