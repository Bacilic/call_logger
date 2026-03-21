import 'dart:convert';

/// Κατάσταση εργασίας (tasks.status).
enum TaskStatus { open, snoozed, closed }

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
    this.callerId,
    this.equipmentId,
    this.departmentId,
    this.phoneId,
    this.phoneText,
    this.userText,
    this.equipmentText,
    this.departmentText,
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
    this.isDeleted = false,
  });

  final int? id;
  final int? callId;
  /// FK προς users.id (ο καλών της σχετικής κλήσης).
  final int? callerId;
  final int? equipmentId;
  final int? departmentId;

  /// Προαιρετικό αναγνωριστικό (π.χ. εσωτερικός αριθμός από τη φόρμα κλήσης).
  final int? phoneId;
  final String? phoneText;
  final String? userText;
  final String? equipmentText;
  final String? departmentText;
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
  final bool isDeleted;

  static DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as int?,
      callId: map['call_id'] as int?,
      callerId: map['caller_id'] as int? ?? map['user_id'] as int?,
      equipmentId: map['equipment_id'] as int?,
      departmentId: map['department_id'] as int?,
      phoneId: map['phone_id'] as int?,
      phoneText: map['phone_text'] as String?,
      userText: map['user_text'] as String?,
      equipmentText: map['equipment_text'] as String?,
      departmentText: map['department_text'] as String?,
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
      isDeleted: (map['is_deleted'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (callId != null) 'call_id': callId,
      if (callerId != null) 'caller_id': callerId,
      if (equipmentId != null) 'equipment_id': equipmentId,
      if (departmentId != null) 'department_id': departmentId,
      if (phoneId != null) 'phone_id': phoneId,
      if (phoneText != null) 'phone_text': phoneText,
      if (userText != null) 'user_text': userText,
      if (equipmentText != null) 'equipment_text': equipmentText,
      if (departmentText != null) 'department_text': departmentText,
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
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  Task copyWith({
    int? id,
    int? callId,
    int? callerId,
    int? equipmentId,
    int? departmentId,
    int? phoneId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
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
    bool? isDeleted,
  }) {
    return Task(
      id: id ?? this.id,
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      equipmentId: equipmentId ?? this.equipmentId,
      departmentId: departmentId ?? this.departmentId,
      phoneId: phoneId ?? this.phoneId,
      phoneText: phoneText ?? this.phoneText,
      userText: userText ?? this.userText,
      equipmentText: equipmentText ?? this.equipmentText,
      departmentText: departmentText ?? this.departmentText,
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
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  /// Ενιαίο κείμενο για ευρετήριο αναζήτησης (τίτλος + πεδία κλήσης / περιγραφή).
  String get combinedSearchText => [
        title,
        description ?? '',
        userText ?? '',
        phoneText ?? '',
        equipmentText ?? '',
        departmentText ?? '',
      ].join(' ');

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
    final entry = TaskSnoozeEntry(snoozedAt: DateTime.now(), dueAt: date);
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

  bool get isOverdue => dueDateTime?.isBefore(DateTime.now()) ?? false;

  bool get isSnoozed =>
      snoozeUntil != null &&
      (_parseDateTime(snoozeUntil)?.isAfter(DateTime.now()) ?? false);
}

class TaskSnoozeEntry {
  const TaskSnoozeEntry({required this.snoozedAt, this.dueAt});

  final DateTime snoozedAt;
  final DateTime? dueAt;
}
