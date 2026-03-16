/// Μοντέλο ορίσματος γραμμής εντολών για εργαλείο απομακρυσμένης σύνδεσης (VNC, AnyDesk).
/// Τα placeholders {TARGET} και {PASSWORD} αντικαθίστανται κατά την εκκίνηση.
class RemoteToolArg {
  RemoteToolArg({
    this.id,
    required this.toolName,
    required this.argFlag,
    required this.description,
    this.isActive = true,
  });

  final int? id;
  final String toolName;
  final String argFlag;
  final String description;
  final bool isActive;

  factory RemoteToolArg.fromMap(Map<String, dynamic> map) {
    return RemoteToolArg(
      id: map['id'] as int?,
      toolName: map['tool_name'] as String? ?? '',
      argFlag: map['arg_flag'] as String? ?? '',
      description: map['description'] as String? ?? '',
      isActive: (map['is_active'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'tool_name': toolName,
      'arg_flag': argFlag,
      'description': description,
      'is_active': isActive ? 1 : 0,
    };
  }

  RemoteToolArg copyWith({
    int? id,
    String? toolName,
    String? argFlag,
    String? description,
    bool? isActive,
  }) {
    return RemoteToolArg(
      id: id ?? this.id,
      toolName: toolName ?? this.toolName,
      argFlag: argFlag ?? this.argFlag,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
    );
  }
}
