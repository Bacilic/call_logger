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
    required this.launchMode,
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
  /// `direct_exec` | `template_file`
  final String launchMode;
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

  /// True όταν το εργαλείο τρέχει ως template file και υπάρχει ενεργό `{FILE}` placeholder.
  bool get acceptsFileParam {
    if (launchMode.trim().toLowerCase() != 'template_file') return false;
    for (final a in arguments) {
      if (!a.isActive) continue;
      if (containsFilePlaceholder(a.value)) return true;
    }
    return false;
  }

  /// Έλεγχος placeholder αρχείου με ανοχή σε πεζά/κεφαλαία (`{FILE}` ή `{file}`).
  static bool containsFilePlaceholder(String value) =>
      value.toLowerCase().contains('{file}');

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
      launchMode: (map['launch_mode'] as String?) ?? 'direct_exec',
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
      'launch_mode': launchMode,
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
    String? launchMode,
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
      launchMode: launchMode ?? this.launchMode,
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
        other.launchMode == launchMode &&
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
        launchMode,
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
