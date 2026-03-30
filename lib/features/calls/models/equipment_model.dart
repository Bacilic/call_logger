import '../utils/vnc_remote_target.dart';

/// Μοντέλο εξοπλισμού (πίνακας equipment): id, code_equipment, type, notes,
/// custom_ip, anydesk_id, default_remote_tool (απομακρυσμένες συνδέσεις),
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
    this.defaultRemoteTool,
    this.departmentId,
    this.location,
    this.isDeleted = false,
  });

  final int? id;
  /// Κωδικός εξοπλισμού (από στήλη code_equipment).
  final String? code;
  final String? type;
  final String? notes;
  /// Προσαρμοσμένη IP για VNC/απομακρυσμένη σύνδεση (exception-based).
  final String? customIp;
  /// AnyDesk ID για απομακρυσμένη σύνδεση.
  final String? anydeskId;
  /// Προεπιλεγμένο εργαλείο απομακρυσμένης σύνδεσης (π.χ. VNC, AnyDesk).
  final String? defaultRemoteTool;
  /// Τμήμα απευθείας στον εξοπλισμό (πίνακας `departments`)· όταν λείπει κάτοχας.
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

  /// Στόχος για VNC: custom IP αν υπάρχει, αλλιώς απευθείας IPv4 στον κωδικό, αλλιώς 'PC{code}', αλλιώς 'Άγνωστο'.
  String get vncTarget {
    final ip = customIp?.trim();
    if (ip != null && ip.isNotEmpty) return ip;
    final c = code?.trim();
    if (c != null && c.isNotEmpty) {
      final asIpv4 = VncRemoteTarget.tryParseIpv4Host(c);
      if (asIpv4 != null) return asIpv4;
      return 'PC$c';
    }
    return 'Άγνωστο';
  }

  /// Στόχος για AnyDesk: επιστρέφει το anydeskId (null αν μη διαθέσιμο).
  String? get anydeskTarget => anydeskId;

  factory EquipmentModel.fromMap(Map<String, dynamic> map) {
    return EquipmentModel(
      id: map['id'] as int?,
      code: (map['code_equipment'] ?? map['code']) as String?,
      type: map['type'] as String?,
      notes: map['notes'] as String?,
      customIp: map['custom_ip'] as String?,
      anydeskId: map['anydesk_id'] as String?,
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
    };
  }

  EquipmentModel copyWith({
    int? id,
    String? code,
    String? type,
    String? notes,
    String? customIp,
    String? anydeskId,
    String? defaultRemoteTool,
    int? departmentId,
    String? location,
    bool? isDeleted,
  }) {
    return EquipmentModel(
      id: id ?? this.id,
      code: code ?? this.code,
      type: type ?? this.type,
      notes: notes ?? this.notes,
      customIp: customIp ?? this.customIp,
      anydeskId: anydeskId ?? this.anydeskId,
      defaultRemoteTool: defaultRemoteTool ?? this.defaultRemoteTool,
      departmentId: departmentId ?? this.departmentId,
      location: location ?? this.location,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
