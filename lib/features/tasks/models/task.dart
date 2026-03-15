/// Κατάσταση εργασίας (tasks.status).
enum TaskStatus {
  open,
  snoozed,
  closed,
}

extension TaskStatusX on TaskStatus {
  static TaskStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'open':
        return TaskStatus.open;
      case 'snoozed':
        return TaskStatus.snoozed;
      case 'closed':
        return TaskStatus.closed;
      default:
        return TaskStatus.open;
    }
  }

  String get toDbValue => switch (this) {
        TaskStatus.open => 'open',
        TaskStatus.snoozed => 'snoozed',
        TaskStatus.closed => 'closed',
      };
}

/// Μοντέλο εργασίας (πίνακας tasks).
class Task {
  Task({
    this.id,
    this.callId,
    this.userId,
    this.equipmentId,
    required this.title,
    this.description,
    required this.dueDate,
    this.snoozeUntil,
    required this.status,
    this.priority,
    this.solutionNotes,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final int? callId;
  final int? userId;
  final int? equipmentId;
  final String title;
  final String? description;
  final String dueDate;
  final String? snoozeUntil;
  final String status;
  final int? priority;
  final String? solutionNotes;
  final String? createdAt;
  final String? updatedAt;

  static DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as int?,
      callId: map['call_id'] as int?,
      userId: map['user_id'] as int?,
      equipmentId: map['equipment_id'] as int?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String?,
      dueDate: map['due_date'] as String? ?? '',
      snoozeUntil: map['snooze_until'] as String?,
      status: map['status'] as String? ?? 'open',
      priority: map['priority'] as int?,
      solutionNotes: map['solution_notes'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (callId != null) 'call_id': callId,
      if (userId != null) 'user_id': userId,
      if (equipmentId != null) 'equipment_id': equipmentId,
      'title': title,
      if (description != null) 'description': description,
      'due_date': dueDate,
      if (snoozeUntil != null) 'snooze_until': snoozeUntil,
      'status': status,
      if (priority != null) 'priority': priority,
      if (solutionNotes != null) 'solution_notes': solutionNotes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  Task copyWith({
    int? id,
    int? callId,
    int? userId,
    int? equipmentId,
    String? title,
    String? description,
    String? dueDate,
    String? snoozeUntil,
    String? status,
    int? priority,
    String? solutionNotes,
    String? createdAt,
    String? updatedAt,
  }) {
    return Task(
      id: id ?? this.id,
      callId: callId ?? this.callId,
      userId: userId ?? this.userId,
      equipmentId: equipmentId ?? this.equipmentId,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      snoozeUntil: snoozeUntil ?? this.snoozeUntil,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      solutionNotes: solutionNotes ?? this.solutionNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  DateTime? get dueDateTime => _parseDateTime(dueDate);
  DateTime? get snoozeUntilDateTime => _parseDateTime(snoozeUntil);
  DateTime? get createdAtDateTime => _parseDateTime(createdAt);
  DateTime? get updatedAtDateTime => _parseDateTime(updatedAt);

  bool get isOverdue =>
      dueDateTime?.isBefore(DateTime.now()) ?? false;

  bool get isSnoozed =>
      snoozeUntil != null &&
      (_parseDateTime(snoozeUntil)?.isAfter(DateTime.now()) ?? false);
}
