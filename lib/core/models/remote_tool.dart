import 'dart:convert';

import 'remote_tool_role.dart';

/// Ένα όρισμα γραμμής εντολών για εργαλείο απομακρυσμένης σύνδεσης (αποθηκεύεται ως JSON).
class RemoteToolArgument {
  const RemoteToolArgument({
    required this.value,
    this.description = '',
    this.isActive = true,
  });

  /// Κείμενο ορίσματος (π.χ. `-host={TARGET}`, `{TARGET}`).
  final String value;
  final String description;
  final bool isActive;

  Map<String, dynamic> toJson() => {
        'value': value,
        'description': description,
        'is_active': isActive,
      };

  factory RemoteToolArgument.fromJson(Map<String, dynamic> json) {
    final v = json['value'] ?? json['arg_flag'];
    return RemoteToolArgument(
      value: v?.toString() ?? '',
      description: (json['description'] ?? '').toString(),
      isActive: _parseBool(json['is_active'] ?? json['isActive']),
    );
  }

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return false;
  }
}

/// Ορισμός εργαλείου απομακρυσμένης σύνδεσης (πίνακας `remote_tools`).
/// // Migrated to placeholders – data-driven (credentials ως plaintext στα `arguments` όπου χρειάζεται).
class RemoteTool {
  const RemoteTool({
    required this.id,
    required this.name,
    required this.role,
    required this.executablePath,
    required this.sortOrder,
    required this.isActive,
    this.deletedAt,
    this.suggestedValuesJson,
    this.iconAssetKey,
    this.arguments = const [],
    this.testTargetIp,
    this.isExclusive = false,
  });

  final int id;
  final String name;
  final ToolRole role;
  final String executablePath;
  final int sortOrder;
  final bool isActive;
  /// Soft delete: όταν μη null, το εργαλείο δεν εμφανίζεται στα ενεργά chips· παραμένει για επιλύσεις id.
  final DateTime? deletedAt;
  final String? suggestedValuesJson;
  final String? iconAssetKey;

  /// Ορίσματα γραμμής εντολών (εναλλακτικά του παλιού πίνακα `remote_tool_args`).
  final List<RemoteToolArgument> arguments;

  /// Δοκιμαστικός στόχος (IP/hostname) για δοκιμή από τη φόρμα· αν είναι κενό, χρησιμοποιούνται οι γενικές ρυθμίσεις ή προεπιλογή.
  final String? testTargetIp;

  /// Όταν true, αν είναι έγκυρο στην κλήση κρύβει τα μη αποκλειστικά εργαλεία.
  final bool isExclusive;

  /// True όταν υπάρχει ενεργό όρισμα με placeholder `{FILE}`.
  bool get acceptsFileParam {
    for (final a in arguments) {
      if (!a.isActive) continue;
      if (containsFilePlaceholder(a.value)) return true;
    }
    return false;
  }

  /// Έλεγχος placeholder αρχείου με ανοχή σε πεζά/κεφαλαία (`{FILE}` ή `{file}`).
  static bool containsFilePlaceholder(String value) =>
      value.toLowerCase().contains('{file}');

  /// Έλεγχος placeholder στόχου με ανοχή σε πεζά/κεφαλαία (`{TARGET}` ή `{target}`).
  static bool containsTargetPlaceholder(String value) =>
      value.toLowerCase().contains('{target}');

  /// Ενεργά ορίσματα για εκτέλεση/δοκιμή: με ενεργό `{FILE}`, παραλείπονται
  /// ενεργά ορίσματα που περιέχουν μόνο `{TARGET}` (όχι στην ίδια τιμή).
  List<RemoteToolArgument> get effectiveActiveArguments {
    final active = arguments.where((a) => a.isActive).toList();
    if (!acceptsFileParam) return active;
    return active
        .where(
          (a) =>
              !containsTargetPlaceholder(a.value) ||
              containsFilePlaceholder(a.value),
        )
        .toList();
  }

  /// Προειδοποίηση Α: σύγκρουση ενεργού {FILE} με ξεχωριστό {TARGET}.
  static String? warningFileTargetConflict(List<RemoteToolArgument> arguments) {
    final active = arguments.where((a) => a.isActive).toList();
    final hasFile = active.any((a) => containsFilePlaceholder(a.value));
    if (!hasFile) return null;
    if (active.any(
      (a) =>
          containsTargetPlaceholder(a.value) &&
          !containsFilePlaceholder(a.value),
    )) {
      return 'Το αρχείο ορίζει τον στόχο — τα ορίσματα με {TARGET} θα αγνοηθούν κατά την εκτέλεση.';
    }
    return null;
  }

  /// Προειδοποίηση Β: διπλότυπες τιμές ενεργών ορισμάτων.
  static String? warningDuplicateActiveArguments(
    List<RemoteToolArgument> arguments,
  ) {
    final seen = <String>{};
    for (final a in arguments) {
      if (!a.isActive) continue;
      final v = a.value.trim();
      if (v.isEmpty) continue;
      if (seen.contains(v)) {
        return 'Υπάρχουν διπλότυπα ορίσματα με την ίδια τιμή.';
      }
      seen.add(v);
    }
    return null;
  }

  /// True όταν κάθε {TARGET} στο όρισμα ακολουθεί αμέσως από `/v:` (χωρίς κενό).
  static bool rdpArgumentHasValidTargetSyntax(String value) {
    final lower = value.toLowerCase();
    const token = '{target}';
    var searchFrom = 0;
    while (true) {
      final pos = lower.indexOf(token, searchFrom);
      if (pos == -1) return true;
      if (pos < 3 || value.substring(pos - 3, pos).toLowerCase() != '/v:') {
        return false;
      }
      searchFrom = pos + token.length;
    }
  }

  /// Προειδοποίηση Γ: λανθασμένη σύνταξη `/v:{TARGET}` για RDP.
  static String? warningRdpTargetSyntax({
    required ToolRole role,
    required List<RemoteToolArgument> arguments,
  }) {
    if (role != ToolRole.rdp) return null;
    for (final a in arguments) {
      if (!a.isActive) continue;
      final v = a.value;
      if (!containsTargetPlaceholder(v) || containsFilePlaceholder(v)) {
        continue;
      }
      if (!rdpArgumentHasValidTargetSyntax(v)) {
        return 'Για RDP ο στόχος γράφεται /v:{TARGET} — κολλητά, χωρίς κενό. '
            'Σκέτο {TARGET} ή "/v: {TARGET}" ερμηνεύεται από το mstsc ως αρχείο σύνδεσης.';
      }
    }
    return null;
  }

  /// Ζωντανές προειδοποιήσεις φόρμας εργαλείου (μία γραμμή ανά εύρημα).
  static List<String> collectArgumentsEditorWarnings({
    required ToolRole role,
    required List<RemoteToolArgument> arguments,
  }) {
    return [
      ?warningFileTargetConflict(arguments),
      ?warningDuplicateActiveArguments(arguments),
      ?warningRdpTargetSyntax(role: role, arguments: arguments),
    ];
  }

  /// Προειδοποίηση φόρμας εργαλείου για συγκρούσεις ορισμάτων (μη μπλοκάρουσα).
  static String? buildArgumentsEditorWarning(
    List<RemoteToolArgument> arguments, {
    required ToolRole role,
  }) {
    final messages = collectArgumentsEditorWarnings(
      role: role,
      arguments: arguments,
    );
    if (messages.isEmpty) return null;
    return messages.join('\n');
  }

  static DateTime? _parseDeletedAt(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static List<RemoteToolArgument> _parseArgumentsJson(dynamic raw) {
    if (raw == null) return const [];
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) {
            if (e is Map<String, dynamic>) {
              return RemoteToolArgument.fromJson(e);
            }
            if (e is Map) {
              return RemoteToolArgument.fromJson(
                e.map((k, v) => MapEntry(k.toString(), v)),
              );
            }
            return null;
          })
          .whereType<RemoteToolArgument>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  factory RemoteTool.fromMap(Map<String, dynamic> map) {
    return RemoteTool(
      id: map['id'] as int,
      name: (map['name'] as String?) ?? '',
      role: toolRoleFromDb(map['role']),
      executablePath: (map['executable_path'] as String?) ?? '',
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isActive: ((map['is_active'] as int?) ?? 0) == 1,
      deletedAt: _parseDeletedAt(map['deleted_at']),
      suggestedValuesJson: map['suggested_values'] as String?,
      iconAssetKey: map['icon_asset_key'] as String?,
      arguments: _parseArgumentsJson(map['arguments_json']),
      testTargetIp: map['test_target_ip'] as String?,
      isExclusive: ((map['is_exclusive'] as int?) ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'role': role.dbValue,
      'executable_path': executablePath,
      'sort_order': sortOrder,
      'is_active': isActive ? 1 : 0,
      'deleted_at': deletedAt?.toIso8601String(),
      'suggested_values': suggestedValuesJson,
      'icon_asset_key': iconAssetKey,
      'arguments_json': _argumentsJsonString(),
      'test_target_ip': testTargetIp,
      'is_exclusive': isExclusive ? 1 : 0,
    };
  }

  String? _argumentsJsonString() {
    if (arguments.isEmpty) return null;
    return jsonEncode(arguments.map((a) => a.toJson()).toList());
  }

  Map<String, dynamic> toInsertMap() {
    final m = Map<String, dynamic>.from(toMap())..remove('id');
    return m;
  }

  RemoteTool copyWith({
    int? id,
    String? name,
    ToolRole? role,
    String? executablePath,
    int? sortOrder,
    bool? isActive,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    String? suggestedValuesJson,
    String? iconAssetKey,
    List<RemoteToolArgument>? arguments,
    String? testTargetIp,
    bool clearTestTargetIp = false,
    bool? isExclusive,
  }) {
    return RemoteTool(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      executablePath: executablePath ?? this.executablePath,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      suggestedValuesJson: suggestedValuesJson ?? this.suggestedValuesJson,
      iconAssetKey: iconAssetKey ?? this.iconAssetKey,
      arguments: arguments ?? this.arguments,
      testTargetIp:
          clearTestTargetIp ? null : (testTargetIp ?? this.testTargetIp),
      isExclusive: isExclusive ?? this.isExclusive,
    );
  }

  static bool _argumentsEqual(
    List<RemoteToolArgument> a,
    List<RemoteToolArgument> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.value != y.value ||
          x.description != y.description ||
          x.isActive != y.isActive) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RemoteTool &&
        other.id == id &&
        other.name == name &&
        other.role == role &&
        other.executablePath == executablePath &&
        other.sortOrder == sortOrder &&
        other.isActive == isActive &&
        other.deletedAt == deletedAt &&
        other.suggestedValuesJson == suggestedValuesJson &&
        other.iconAssetKey == iconAssetKey &&
        other.testTargetIp == testTargetIp &&
        other.isExclusive == isExclusive &&
        _argumentsEqual(other.arguments, arguments);
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        role,
        executablePath,
        sortOrder,
        isActive,
        deletedAt,
        suggestedValuesJson,
        iconAssetKey,
        testTargetIp,
        isExclusive,
        Object.hashAll(
          arguments.map(
            (a) => Object.hash(a.value, a.description, a.isActive),
          ),
        ),
      );
}
