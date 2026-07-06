import 'dart:convert';

import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_role.dart';
import '../utils/equipment_remote_param_key.dart';
import '../utils/vnc_remote_target.dart';

/// Μοντέλο εξοπλισμού (πίνακας equipment): id, code_equipment, type, notes,
/// remote_params (JSON με κλειδιά `<remote_tools.id>`), default_remote_tool,
/// department_id / location.
class EquipmentModel {
  EquipmentModel({
    this.id,
    this.code,
    this.type,
    this.notes,
    Map<String, String> remoteParams = const {},
    this.defaultRemoteTool,
    this.departmentId,
    this.location,
    this.isDeleted = false,
  }) : remoteParams = Map<String, String>.unmodifiable(
          Map<String, String>.from(remoteParams),
        );

  final int? id;
  /// Κωδικός εξοπλισμού (από στήλη code_equipment).
  final String? code;
  final String? type;
  final String? notes;
  /// Παράμετροι ανά εργαλείο (κλειδί = `remote_tools.id` ως string).
  final Map<String, String> remoteParams;
  /// Προεπιλεγμένο εργαλείο απομακρυσμένης σύνδεσης (`remote_tools.id`).
  final String? defaultRemoteTool;
  /// Τμήμα απευθείας στον εξοπλισμό (πίνακας `departments`)· όταν λείπει κάτοχος.
  final int? departmentId;
  /// Τοποθεσία απευθείας στον εξοπλισμό (`equipment.location`).
  final String? location;
  final bool isDeleted;

  /// Για εμφάνιση σε λίστες (κωδικός + τύπος).
  String get displayLabel {
    final c = code?.trim() ?? '';
    final t = type?.trim() ?? '';
    return t.isEmpty ? c : (c.isEmpty ? t : '$c ($t)');
  }

  String? paramForTool(RemoteTool tool) {
    final v = remoteParams[tool.id.toString()]?.trim();
    if (v != null && v.isNotEmpty) return v;
    return null;
  }

  /// Πρώτο επιλεγμένο εργαλείο κατά σειρά ταξινόμησης — ίδια λογική με chips στη φόρμα.
  int? effectiveDefaultRemoteToolId(List<RemoteTool> catalog) {
    final selected = <RemoteTool>[];
    for (final entry in remoteParams.entries) {
      if (EquipmentRemoteParamKey.isReservedKey(entry.key)) continue;
      final id = int.tryParse(entry.key);
      if (id == null) continue;
      for (final t in catalog) {
        if (t.id == id) {
          selected.add(t);
          break;
        }
      }
    }
    selected.sort((a, b) {
      final cmp = a.sortOrder.compareTo(b.sortOrder);
      if (cmp != 0) return cmp;
      return a.name.compareTo(b.name);
    });
    return selected.isEmpty ? null : selected.first.id;
  }

  /// Αληθές όταν το αποθηκευμένο `default_remote_tool` δεν ταιριάζει με το effective.
  bool hasInconsistentDefaultRemoteTool(List<RemoteTool> catalog) {
    final storedId = int.tryParse(defaultRemoteTool?.trim() ?? '');
    if (storedId == null) return false;
    return storedId != effectiveDefaultRemoteToolId(catalog);
  }

  /// Το «κύριο» εργαλείο που εμφανίζεται στη λίστα, **υπολογιζόμενο** (όχι από το
  /// αποθηκευμένο `default_remote_tool`): αποκλειστικό εργαλείο ανά εξοπλισμό αν έχει
  /// οριστεί και υπάρχει στον κατάλογο, αλλιώς το πρώτο με παράμετρο κατά σειρά
  /// ταξινόμησης ([effectiveDefaultRemoteToolId]).
  int? displayPrimaryRemoteToolId(List<RemoteTool> catalog) {
    final exclusiveId =
        EquipmentRemoteParamKey.exclusiveToolIdFrom(remoteParams);
    if (exclusiveId != null) {
      for (final t in catalog) {
        if (t.id == exclusiveId) return exclusiveId;
      }
    }
    return effectiveDefaultRemoteToolId(catalog);
  }

  RemoteTool? _preferredToolForRole(List<RemoteTool> tools, ToolRole role) {
    final prefId = int.tryParse(defaultRemoteTool?.trim() ?? '');
    if (prefId != null) {
      for (final t in tools) {
        if (t.id == prefId && t.role == role) return t;
      }
    }
    for (final t in tools) {
      if (t.role == role) return t;
    }
    return null;
  }

  /// VNC / `vnc_host`: τιμή από `remote_params[<tool.id>]`· αλλιώς κωδικός + πρόθεμα `PC`.
  String vncLikeTargetResolved(RemoteTool? forTool) {
    const prefix = 'PC';
    if (forTool != null) {
      final byId = paramForTool(forTool);
      if (byId != null) {
        final resolved = VncRemoteTarget.resolveValidVncHost(
          byId,
          prefix: prefix,
        );
        if (resolved != null) return resolved;
      }
    }
    final c = code?.trim();
    if (c != null && c.isNotEmpty) {
      final resolved = VncRemoteTarget.resolveValidVncHost(c, prefix: prefix);
      if (resolved != null) return resolved;
    }
    return 'Άγνωστο';
  }

  String vncTargetResolved(List<RemoteTool> tools) =>
      vncLikeTargetResolved(_preferredToolForRole(tools, ToolRole.vnc));

  String? rdpHostResolved(List<RemoteTool> tools) {
    final rdpTool = _preferredToolForRole(tools, ToolRole.rdp);
    if (rdpTool == null) return null;
    return paramForTool(rdpTool);
  }

  String? anydeskIdResolved(List<RemoteTool> tools) {
    final adTool = _preferredToolForRole(tools, ToolRole.anydesk);
    if (adTool == null) return null;
    return paramForTool(adTool);
  }

  static Map<String, String> _parseRemoteParamsColumn(Object? raw) {
    if (raw == null) return {};
    final s = raw is String ? raw.trim() : raw.toString().trim();
    if (s.isEmpty) return {};
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        if (k == null || v == null) return;
        final key = k.toString().trim();
        if (key.isEmpty) return;
        out[key] = v.toString();
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  factory EquipmentModel.fromMap(Map<String, dynamic> map) {
    final parsed = _parseRemoteParamsColumn(map['remote_params']);
    return EquipmentModel(
      id: map['id'] as int?,
      code: (map['code_equipment'] ?? map['code']) as String?,
      type: map['type'] as String?,
      notes: map['notes'] as String?,
      remoteParams: Map<String, String>.unmodifiable(parsed),
      defaultRemoteTool: map['default_remote_tool'] as String?,
      departmentId: map['department_id'] as int?,
      location: map['location'] as String?,
      isDeleted: (map['is_deleted'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (code != null) 'code_equipment': code,
      if (type != null) 'type': type,
      if (notes != null) 'notes': notes,
      'default_remote_tool': defaultRemoteTool,
      'department_id': departmentId,
      'location': location,
      'is_deleted': isDeleted ? 1 : 0,
      'remote_params': remoteParams.isEmpty ? null : jsonEncode(remoteParams),
    };
  }

  EquipmentModel copyWith({
    int? id,
    String? code,
    String? type,
    String? notes,
    Map<String, String>? remoteParams,
    String? defaultRemoteTool,
    int? departmentId,
    String? location,
    bool? isDeleted,
  }) {
    final nextRemote = remoteParams ?? this.remoteParams;
    return EquipmentModel(
      id: id ?? this.id,
      code: code ?? this.code,
      type: type ?? this.type,
      notes: notes ?? this.notes,
      remoteParams: Map<String, String>.from(nextRemote),
      defaultRemoteTool: defaultRemoteTool ?? this.defaultRemoteTool,
      departmentId: departmentId ?? this.departmentId,
      location: location ?? this.location,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
