/// Μοντέλο ορίσματος γραμμής εντολών για εργαλείο απομακρυσμένης σύνδεσης (VNC, AnyDesk).
/// Τα placeholders {TARGET} και {PASSWORD} αντικαθίστανται κατά την εκκίνηση.
class RemoteToolArg {
  RemoteToolArg({
    this.id,
    this.remoteToolId,
    required this.toolName,
    required this.argFlag,
    required this.description,
    this.isActive = true,
  });

  final int? id;
  final int? remoteToolId;
  final String toolName;
  final String argFlag;
  final String description;
  final bool isActive;

  factory RemoteToolArg.fromMap(Map<String, dynamic> map) {
    return RemoteToolArg(
      id: map['id'] as int?,
      remoteToolId: map['remote_tool_id'] as int?,
      toolName: map['tool_name'] as String? ?? '',
      argFlag: map['arg_flag'] as String? ?? '',
      description: map['description'] as String? ?? '',
      isActive: (map['is_active'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (remoteToolId != null) 'remote_tool_id': remoteToolId,
      'tool_name': toolName,
      'arg_flag': argFlag,
      'description': description,
      'is_active': isActive ? 1 : 0,
    };
  }

  RemoteToolArg copyWith({
    int? id,
    int? remoteToolId,
    String? toolName,
    String? argFlag,
    String? description,
    bool? isActive,
  }) {
    return RemoteToolArg(
      id: id ?? this.id,
      remoteToolId: remoteToolId ?? this.remoteToolId,
      toolName: toolName ?? this.toolName,
      argFlag: argFlag ?? this.argFlag,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
    );
  }
}
