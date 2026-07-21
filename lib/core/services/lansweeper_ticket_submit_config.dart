import 'dart:convert';

/// Τύπος widget για custom πεδίο φόρμας Lansweeper.
enum LansweeperFieldWidgetType {
  dropdown,
  radio,
  text;

  static LansweeperFieldWidgetType fromStorage(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'dropdown':
        return LansweeperFieldWidgetType.dropdown;
      case 'radio':
        return LansweeperFieldWidgetType.radio;
      case 'text':
        return LansweeperFieldWidgetType.text;
      default:
        return LansweeperFieldWidgetType.text;
    }
  }

  String toStorage() => name;
}

/// Ορισμός custom πεδίου στη ροή καταχώρησης ticket Lansweeper.
class LansweeperCustomFieldDef {
  const LansweeperCustomFieldDef({
    required this.id,
    required this.apiName,
    required this.formLabel,
    required this.widgetType,
    this.options = const [],
    this.defaultValue = '',
    this.visible = true,
    this.required = false,
    this.showInForm = true,
  });

  final String id;
  final String apiName;
  final String formLabel;
  final LansweeperFieldWidgetType widgetType;
  final List<String> options;
  final String defaultValue;
  final bool visible;
  final bool required;
  final bool showInForm;

  LansweeperCustomFieldDef copyWith({
    String? id,
    String? apiName,
    String? formLabel,
    LansweeperFieldWidgetType? widgetType,
    List<String>? options,
    String? defaultValue,
    bool? visible,
    bool? required,
    bool? showInForm,
  }) {
    return LansweeperCustomFieldDef(
      id: id ?? this.id,
      apiName: apiName ?? this.apiName,
      formLabel: formLabel ?? this.formLabel,
      widgetType: widgetType ?? this.widgetType,
      options: options ?? this.options,
      defaultValue: defaultValue ?? this.defaultValue,
      visible: visible ?? this.visible,
      required: required ?? this.required,
      showInForm: showInForm ?? this.showInForm,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'api_name': apiName,
        'form_label': formLabel,
        'widget_type': widgetType.toStorage(),
        'options': options,
        'default_value': defaultValue,
        'visible': visible,
        'required': required,
        'show_in_form': showInForm,
      };

  static LansweeperCustomFieldDef fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = <String>[];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        if (item != null) options.add(item.toString());
      }
    }

    return LansweeperCustomFieldDef(
      id: json['id']?.toString() ?? '',
      apiName: json['api_name']?.toString() ?? '',
      formLabel: json['form_label']?.toString() ?? '',
      widgetType: LansweeperFieldWidgetType.fromStorage(
        json['widget_type']?.toString() ?? '',
      ),
      options: options,
      defaultValue: json['default_value']?.toString() ?? '',
      visible: json['visible'] is bool ? json['visible'] as bool : true,
      required: json['required'] is bool ? json['required'] as bool : false,
      showInForm:
          json['show_in_form'] is bool ? json['show_in_form'] as bool : true,
    );
  }
}

/// Παραμετροποίηση πολυβηματικής καταχώρησης ticket Lansweeper.
class LansweeperTicketSubmitConfig {
  const LansweeperTicketSubmitConfig({
    required this.schemaVersion,
    required this.customFields,
    required this.ticketStates,
    required this.defaultTicketState,
    required this.noteType,
    required this.ticketType,
    required this.ticketTypes,
    required this.priority,
    required this.priorities,
    required this.team,
    required this.teams,
    required this.enableAddNoteStep,
    required this.enableStateUpdateStep,
    required this.rememberFormSelections,
    required this.includeNoteTime,
  });

  static const List<String> defaultTicketTypes = ['IT Support'];
  static const List<String> defaultPriorities = ['Low', 'Medium', 'High'];
  static const List<String> defaultTeams = ['IT Support'];

  final int schemaVersion;
  final List<LansweeperCustomFieldDef> customFields;
  final List<String> ticketStates;
  final String defaultTicketState;
  final String noteType;
  final String ticketType;
  final List<String> ticketTypes;
  final String priority;
  final List<String> priorities;
  final String team;
  final List<String> teams;
  final bool enableAddNoteStep;
  final bool enableStateUpdateStep;
  final bool rememberFormSelections;
  final bool includeNoteTime;

  factory LansweeperTicketSubmitConfig.defaults() {
    return LansweeperTicketSubmitConfig(
      schemaVersion: 2,
      ticketStates: const ['Open', 'Closed', 'In Progress'],
      defaultTicketState: 'Closed',
      noteType: 'Internal',
      ticketType: 'IT Support',
      ticketTypes: defaultTicketTypes,
      priority: 'Low',
      priorities: defaultPriorities,
      team: 'IT Support',
      teams: defaultTeams,
      enableAddNoteStep: true,
      enableStateUpdateStep: true,
      rememberFormSelections: true,
      includeNoteTime: true,
      customFields: const [
        LansweeperCustomFieldDef(
          id: 'category',
          apiName: 'Κατηγορία αιτήματος',
          formLabel: 'Κατηγορία αιτήματος',
          widgetType: LansweeperFieldWidgetType.radio,
          options: ['Yes', 'No'],
          defaultValue: 'Yes',
          visible: true,
          required: true,
          showInForm: true,
        ),
        LansweeperCustomFieldDef(
          id: 'incident_category',
          apiName: 'Τί αφορά;',
          formLabel: 'Τί αφορά;',
          widgetType: LansweeperFieldWidgetType.dropdown,
          options: [
            'Hardware στα Endpoints (PCs, Printers κλπ.)',
            'Software γενικού σκοπού στα Endpoints',
            'Δικτύωση (Ενδοδίκτυο, Internet)',
            'Datacenter (Server, NAS κλπ.)',
            'Δομημένη Καλωδιακή Υποδομή',
            'UPS, Power issues',
            'Εφαρμογές Ειδικού Σκοπού (Datamed, Docutracks κλπ.)',
          ],
          defaultValue: 'Software γενικού σκοπού στα Endpoints',
          visible: true,
          required: true,
          showInForm: true,
        ),
      ],
    );
  }

  LansweeperTicketSubmitConfig copyWith({
    int? schemaVersion,
    List<LansweeperCustomFieldDef>? customFields,
    List<String>? ticketStates,
    String? defaultTicketState,
    String? noteType,
    String? ticketType,
    List<String>? ticketTypes,
    String? priority,
    List<String>? priorities,
    String? team,
    List<String>? teams,
    bool? enableAddNoteStep,
    bool? enableStateUpdateStep,
    bool? rememberFormSelections,
    bool? includeNoteTime,
  }) {
    return LansweeperTicketSubmitConfig(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      customFields: customFields ?? this.customFields,
      ticketStates: ticketStates ?? this.ticketStates,
      defaultTicketState: defaultTicketState ?? this.defaultTicketState,
      noteType: noteType ?? this.noteType,
      ticketType: ticketType ?? this.ticketType,
      ticketTypes: ticketTypes ?? this.ticketTypes,
      priority: priority ?? this.priority,
      priorities: priorities ?? this.priorities,
      team: team ?? this.team,
      teams: teams ?? this.teams,
      enableAddNoteStep: enableAddNoteStep ?? this.enableAddNoteStep,
      enableStateUpdateStep:
          enableStateUpdateStep ?? this.enableStateUpdateStep,
      rememberFormSelections:
          rememberFormSelections ?? this.rememberFormSelections,
      includeNoteTime: includeNoteTime ?? this.includeNoteTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'custom_fields': customFields.map((f) => f.toJson()).toList(),
        'ticket_states': ticketStates,
        'default_ticket_state': defaultTicketState,
        'note_type': noteType,
        'ticket_type': ticketType,
        'ticket_types': ticketTypes,
        'priority': priority,
        'priorities': priorities,
        'team': team,
        'teams': teams,
        'enable_add_note_step': enableAddNoteStep,
        'enable_state_update_step': enableStateUpdateStep,
        'remember_form_selections': rememberFormSelections,
        'include_note_time': includeNoteTime,
      };

  static List<String> _stringList(Object? raw) {
    final out = <String>[];
    if (raw is List) {
      for (final item in raw) {
        if (item != null) {
          final text = item.toString().trim();
          if (text.isNotEmpty) out.add(text);
        }
      }
    }
    return out;
  }

  /// Ασφαλής ανάγνωση bool (snake_case ή camelCase)· null/άγνωστο → [defaultValue].
  static bool _readBool(
    Map<String, dynamic> json,
    String snakeKey, {
    String? camelKey,
    required bool defaultValue,
  }) {
    final raw = json.containsKey(snakeKey)
        ? json[snakeKey]
        : (camelKey != null ? json[camelKey] : null);
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return defaultValue;
  }

  /// Εξασφαλίζει ότι η επιλεγμένη τιμή υπάρχει στη λίστα (αλλιώς στην αρχή).
  static List<String> ensureSelectedInList(
    List<String> list,
    String selected, {
    required List<String> fallbackList,
  }) {
    final normalizedSelected = selected.trim();
    var next = list.isEmpty
        ? List<String>.from(fallbackList)
        : List<String>.from(list);
    if (normalizedSelected.isEmpty) return next;
    if (!next.contains(normalizedSelected)) {
      next = [normalizedSelected, ...next];
    }
    return next;
  }

  static LansweeperTicketSubmitConfig fromJson(Map<String, dynamic> json) {
    final rawFields = json['custom_fields'] ?? json['customFields'];
    final customFields = <LansweeperCustomFieldDef>[];
    if (rawFields is List) {
      for (final item in rawFields) {
        if (item is Map<String, dynamic>) {
          customFields.add(LansweeperCustomFieldDef.fromJson(item));
        } else if (item is Map) {
          customFields.add(
            LansweeperCustomFieldDef.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }

    final ticketStates = _stringList(
      json['ticket_states'] ?? json['ticketStates'],
    );
    final ticketType =
        (json['ticket_type'] ?? json['ticketType'])?.toString() ?? 'IT Support';
    final priority = json['priority']?.toString() ?? 'Low';
    final team = json['team']?.toString() ?? 'IT Support';

    final ticketTypes = ensureSelectedInList(
      _stringList(json['ticket_types'] ?? json['ticketTypes']),
      ticketType,
      fallbackList: defaultTicketTypes,
    );
    final priorities = ensureSelectedInList(
      _stringList(json['priorities']),
      priority,
      fallbackList: defaultPriorities,
    );
    final teams = ensureSelectedInList(
      _stringList(json['teams']),
      team,
      fallbackList: defaultTeams,
    );

    return LansweeperTicketSubmitConfig(
      schemaVersion: 2,
      customFields: customFields,
      ticketStates: ticketStates.isEmpty
          ? const ['Open', 'Closed', 'In Progress']
          : ticketStates,
      defaultTicketState:
          (json['default_ticket_state'] ?? json['defaultTicketState'])
                  ?.toString() ??
              'Closed',
      noteType:
          (json['note_type'] ?? json['noteType'])?.toString() ?? 'Internal',
      ticketType: ticketType,
      ticketTypes: ticketTypes,
      priority: priority,
      priorities: priorities,
      team: team,
      teams: teams,
      enableAddNoteStep: _readBool(
        json,
        'enable_add_note_step',
        camelKey: 'enableAddNoteStep',
        defaultValue: true,
      ),
      enableStateUpdateStep: _readBool(
        json,
        'enable_state_update_step',
        camelKey: 'enableStateUpdateStep',
        defaultValue: true,
      ),
      rememberFormSelections: _readBool(
        json,
        'remember_form_selections',
        camelKey: 'rememberFormSelections',
        defaultValue: true,
      ),
      includeNoteTime: _readBool(
        json,
        'include_note_time',
        camelKey: 'includeNoteTime',
        defaultValue: true,
      ),
    );
  }

  static String encodeForStorage(LansweeperTicketSubmitConfig config) =>
      jsonEncode(config.toJson());

  static LansweeperTicketSubmitConfig decodeFromStorage(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return LansweeperTicketSubmitConfig.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return LansweeperTicketSubmitConfig.defaults();
      }
      return fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return LansweeperTicketSubmitConfig.defaults();
    }
  }

  /// Επιστρέφει τα ids των required πεδίων με κενή ή ελλιπή τιμή.
  List<String> missingRequiredFields(Map<String, String> valuesByFieldId) {
    final missing = <String>[];
    for (final field in customFields) {
      if (!field.required) continue;
      final value = valuesByFieldId[field.id]?.trim() ?? '';
      if (value.isEmpty) missing.add(field.id);
    }
    return missing;
  }
}
