/// Μοντέλο εξοπλισμού (πίνακας equipment): id, code_equipment, type, user_id, notes,
/// custom_ip, anydesk_id, default_remote_tool (απομακρυσμένες συνδέσεις).
class EquipmentModel {
  EquipmentModel({
    this.id,
    this.code,
    this.type,
    this.notes,
    this.userId,
    this.customIp,
    this.anydeskId,
    this.defaultRemoteTool,
  });

  final int? id;
  /// Κωδικός εξοπλισμού (από στήλη code_equipment).
  final String? code;
  final String? type;
  final String? notes;
  final int? userId;
  /// Προσαρμοσμένη IP για VNC/απομακρυσμένη σύνδεση (exception-based).
  final String? customIp;
  /// AnyDesk ID για απομακρυσμένη σύνδεση.
  final String? anydeskId;
  /// Προεπιλεγμένο εργαλείο απομακρυσμένης σύνδεσης (π.χ. VNC, AnyDesk).
  final String? defaultRemoteTool;

  /// Για εμφάνιση σε λίστες (κωδικός + τύπος).
  String get displayLabel {
    final c = code?.trim() ?? '';
    final t = type?.trim() ?? '';
    return t.isEmpty ? c : (c.isEmpty ? t : '$c ($t)');
  }

  /// Στόχος για VNC: custom IP αν υπάρχει, αλλιώς 'PC{code}', αλλιώς 'Άγνωστο'.
  String get vncTarget {
    final ip = customIp?.trim();
    if (ip != null && ip.isNotEmpty) return ip;
    final c = code?.trim();
    if (c != null && c.isNotEmpty) return 'PC$c';
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
      userId: map['user_id'] as int?,
      customIp: map['custom_ip'] as String?,
      anydeskId: map['anydesk_id'] as String?,
      defaultRemoteTool: map['default_remote_tool'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (code != null) 'code_equipment': code,
      if (type != null) 'type': type,
      if (notes != null) 'notes': notes,
      if (userId != null) 'user_id': userId,
      if (customIp != null) 'custom_ip': customIp,
      if (anydeskId != null) 'anydesk_id': anydeskId,
      if (defaultRemoteTool != null) 'default_remote_tool': defaultRemoteTool,
    };
  }

  EquipmentModel copyWith({
    int? id,
    String? code,
    String? type,
    String? notes,
    int? userId,
    String? customIp,
    String? anydeskId,
    String? defaultRemoteTool,
  }) {
    return EquipmentModel(
      id: id ?? this.id,
      code: code ?? this.code,
      type: type ?? this.type,
      notes: notes ?? this.notes,
      userId: userId ?? this.userId,
      customIp: customIp ?? this.customIp,
      anydeskId: anydeskId ?? this.anydeskId,
      defaultRemoteTool: defaultRemoteTool ?? this.defaultRemoteTool,
    );
  }
}
