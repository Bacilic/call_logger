import 'dart:convert';

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

  /// Ετικέτα για το UI (η DB κρατά αγγλικά κλειδιά).
  String get displayLabelEl => switch (this) {
        TaskStatus.open => 'ανοικτή',
        TaskStatus.snoozed => 'αναβληθείσα',
        TaskStatus.closed => 'ολοκληρωμένη',
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
    this.snoozeHistoryJson,
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
  final String? snoozeHistoryJson;
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
      snoozeHistoryJson: map['snooze_history_json'] as String?,
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
      if (snoozeHistoryJson != null) 'snooze_history_json': snoozeHistoryJson,
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
    String? snoozeHistoryJson,
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
      snoozeHistoryJson: snoozeHistoryJson ?? this.snoozeHistoryJson,
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

  /// Ιστορικό αναβολών (συμβατό με παλιό format λίστας από ISO strings).
  /// Νέο format: [{"snoozedAt":"...","dueAt":"..."}].
  List<TaskSnoozeEntry> get snoozeEntries {
    final raw = snoozeHistoryJson;
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final entries = <TaskSnoozeEntry>[];
      for (final item in decoded) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final snoozedAt = _parseDateTime(map['snoozedAt']?.toString());
          final dueAt = _parseDateTime(map['dueAt']?.toString());
          if (snoozedAt != null) {
            entries.add(TaskSnoozeEntry(snoozedAt: snoozedAt, dueAt: dueAt));
          }
          continue;
        }
        final asDate = DateTime.tryParse(item.toString());
        if (asDate != null) {
          // Backward compatibility: παλιό format όπου το item ήταν το νέο due date.
          entries.add(TaskSnoozeEntry(snoozedAt: asDate, dueAt: asDate));
        }
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }

  List<DateTime> get snoozeHistory =>
      snoozeEntries.map((e) => e.dueAt ?? e.snoozedAt).toList();

  /// Επιστρέφει νέο Task με append στο ιστορικό αναβολών.
  Task addSnoozeEntry(DateTime date) {
    final entry = TaskSnoozeEntry(
      snoozedAt: DateTime.now(),
      dueAt: date,
    );
    final next = [...snoozeEntries, entry]
        .map(
          (e) => {
            'snoozedAt': e.snoozedAt.toIso8601String(),
            if (e.dueAt != null) 'dueAt': e.dueAt!.toIso8601String(),
          },
        )
        .toList();
    return copyWith(snoozeHistoryJson: jsonEncode(next));
  }

  bool get isOverdue =>
      dueDateTime?.isBefore(DateTime.now()) ?? false;

  bool get isSnoozed =>
      snoozeUntil != null &&
      (_parseDateTime(snoozeUntil)?.isAfter(DateTime.now()) ?? false);
}

class TaskSnoozeEntry {
  const TaskSnoozeEntry({
    required this.snoozedAt,
    this.dueAt,
  });

  final DateTime snoozedAt;
  final DateTime? dueAt;
}
