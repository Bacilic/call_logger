import 'dart:convert';

import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_role.dart';
import '../utils/equipment_remote_param_key.dart';
import '../utils/vnc_remote_target.dart';

/// Μοντέλο εξοπλισμού (πίνακας equipment): id, code_equipment, type, notes,
/// custom_ip, anydesk_id, remote_params (JSON), default_remote_tool (απομακρυσμένες συνδέσεις),
/// department_id / location (κοινόχρηστα μηχανήματα χωρίς κάτοχο· fallback στο UI).
/// Η αντιστοίχιση χρήστη–εξοπλισμού γίνεται στον πίνακα [user_equipment] (M2M).
class EquipmentModel {
  EquipmentModel({
    this.id,
    this.code,
    this.type,
    this.notes,
    this.customIp,
    this.anydeskId,
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
  /// Προσαρμοσμένη IP για VNC/απομακρυσμένη σύνδεση (legacy στήλη· συγχρονίζεται με [remoteParams][vnc]).
  final String? customIp;
  /// AnyDesk ID (legacy στήλη· συγχρονίζεται με [remoteParams][anydesk]).
  final String? anydeskId;
  /// Παράμετροι ανά εργαλείο (κλειδί → τιμή), αποθηκευμένα ως JSON στη στήλη `remote_params`.
  final Map<String, String> remoteParams;
  /// Προεπιλεγμένο εργαλείο απομακρυσμένης σύνδεσης (π.χ. VNC, AnyDesk).
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

  /// AnyDesk ID: προτεραιότητα [remoteParams][anydesk], αλλιώς [anydeskId].
  String? get displayAnydeskId {
    final fromJson = remoteParams[EquipmentRemoteParamKey.anydesk]?.trim();
    if (fromJson != null && fromJson.isNotEmpty) return fromJson;
    final leg = anydeskId?.trim();
    if (leg != null && leg.isNotEmpty) return leg;
    return null;
  }

  /// Στόχος VNC (host/IP): προτεραιότητα [remoteParams][vnc], αλλιώς [customIp].
  String? get displayCustomIp {
    final fromJson = remoteParams[EquipmentRemoteParamKey.vnc]?.trim();
    if (fromJson != null && fromJson.isNotEmpty) {
      final resolved = VncRemoteTarget.resolveValidVncHost(fromJson);
      if (resolved != null) return resolved;
    }
    final leg = customIp?.trim();
    if (leg != null && leg.isNotEmpty) {
      final resolved = VncRemoteTarget.resolveValidVncHost(leg);
      if (resolved != null) return resolved;
    }
    return null;
  }

  /// Στόχος για VNC: προσαρμοσμένη IP αν υπάρχει, αλλιώς απευθείας IPv4 στον κωδικό, αλλιώς 'PC{code}', αλλιώς 'Άγνωστο'.
  /// Δεν διαβάζει κλειδιά numeric `remote_tools.id` — χρησιμοποιήστε [vncTargetResolved].
  String get vncTarget {
    final ip = displayCustomIp;
    if (ip != null && ip.isNotEmpty) return ip;
    final c = code?.trim();
    if (c != null && c.isNotEmpty) {
      final resolved = VncRemoteTarget.resolveValidVncHost(c);
      if (resolved != null) return resolved;
    }
    return 'Άγνωστο';
  }

  /// VNC / `vnc_host`: dual-read τιμής + πρόθεμα host από το συγκεκριμένο [forTool] (ή προεπιλογή `PC`).
  String vncLikeTargetResolved(RemoteTool? forTool) {
    if (forTool != null) {
      final byId = remoteParams[forTool.id.toString()]?.trim();
      if (byId != null && byId.isNotEmpty) {
        final resolved = VncRemoteTarget.resolveValidVncHost(
          byId,
          prefix: (forTool.vncHostPrefix?.trim().isNotEmpty ?? false)
              ? forTool.vncHostPrefix!.trim()
              : 'PC',
        );
        if (resolved != null) return resolved;
      }
    }
    if (forTool == null || forTool.role == ToolRole.vnc) {
      final legacy = displayCustomIp;
      if (legacy != null && legacy.isNotEmpty) return legacy;
    }
    final c = code?.trim();
    if (c != null && c.isNotEmpty) {
      final prefix = (forTool?.vncHostPrefix?.trim().isNotEmpty ?? false)
          ? forTool!.vncHostPrefix!.trim()
          : 'PC';
      final resolved = VncRemoteTarget.resolveValidVncHost(c, prefix: prefix);
      if (resolved != null) return resolved;
    }
    return 'Άγνωστο';
  }

  /// VNC host με dual-read: `remote_params[vncTool.id]`, μετά legacy, μετά κωδικός + πρόθεμα από ορισμό εργαλείου VNC.
  String vncTargetResolved(List<RemoteTool> tools) {
    RemoteTool? vncTool;
    final prefId = int.tryParse(defaultRemoteTool?.trim() ?? '');
    if (prefId != null) {
      for (final t in tools) {
        if (t.id == prefId && t.role == ToolRole.vnc) {
          vncTool = t;
          break;
        }
      }
    }
    vncTool ??= () {
      for (final t in tools) {
        if (t.role == ToolRole.vnc) return t;
      }
      return null;
    }();
    return vncLikeTargetResolved(vncTool);
  }

  /// Στόχος RDP (διακομιστής): `remote_params[rdp.id]` μετά legacy `rdp`.
  String? rdpHostResolved(List<RemoteTool> tools) {
    RemoteTool? rdpTool;
    final prefId = int.tryParse(defaultRemoteTool?.trim() ?? '');
    if (prefId != null) {
      for (final t in tools) {
        if (t.id == prefId && t.role == ToolRole.rdp) {
          rdpTool = t;
          break;
        }
      }
    }
    rdpTool ??= () {
      for (final t in tools) {
        if (t.role == ToolRole.rdp) return t;
      }
      return null;
    }();
    if (rdpTool != null) {
      final byId = remoteParams[rdpTool.id.toString()]?.trim();
      if (byId != null && byId.isNotEmpty) return byId;
    }
    final leg = remoteParams[EquipmentRemoteParamKey.rdp]?.trim();
    if (leg != null && leg.isNotEmpty) return leg;
    return null;
  }

  /// Στόχος για AnyDesk: επιστρέφει το ID (null αν μη διαθέσιμο).
  String? get anydeskTarget => displayAnydeskId;

  /// AnyDesk ID με dual-read: `remote_params[anydeskTool.id]` μετά legacy στήλες/κλειδιά.
  String? anydeskIdResolved(List<RemoteTool> tools) {
    RemoteTool? adTool;
    final prefId = int.tryParse(defaultRemoteTool?.trim() ?? '');
    if (prefId != null) {
      for (final t in tools) {
        if (t.id == prefId && t.role == ToolRole.anydesk) {
          adTool = t;
          break;
        }
      }
    }
    adTool ??= () {
      for (final t in tools) {
        if (t.role == ToolRole.anydesk) return t;
      }
      return null;
    }();
    if (adTool != null) {
      final byId = remoteParams[adTool.id.toString()]?.trim();
      if (byId != null && byId.isNotEmpty) return byId;
    }
    return displayAnydeskId;
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
      customIp: map['custom_ip'] as String?,
      anydeskId: map['anydesk_id'] as String?,
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
      if (customIp != null) 'custom_ip': customIp,
      if (anydeskId != null) 'anydesk_id': anydeskId,
      if (defaultRemoteTool != null) 'default_remote_tool': defaultRemoteTool,
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
    String? customIp,
    String? anydeskId,
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
      customIp: customIp ?? this.customIp,
      anydeskId: anydeskId ?? this.anydeskId,
      remoteParams: Map<String, String>.from(nextRemote),
      defaultRemoteTool: defaultRemoteTool ?? this.defaultRemoteTool,
      departmentId: departmentId ?? this.departmentId,
      location: location ?? this.location,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
