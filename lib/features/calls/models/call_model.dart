import '../../../core/utils/history_entity_display_utils.dart';

/// Μοντέλο κλήσης (πίνακας calls).
class CallModel {
  CallModel({
    this.id,
    this.date,
    this.time,
    this.callerId,
    this.equipmentId,
    this.callerText,
    this.phoneText,
    this.departmentText,
    this.equipmentText,
    this.issue,
    this.solution,
    this.category,
    this.categoryId,
    this.status,
    this.duration,
    this.isPriority,
    this.lansweeperState,
    this.lansweeperMainTicketId,
    this.lansweeperLastSyncAt,
    this.isDeleted = false,
    this.callerLinkedDeleted = false,
    this.equipmentLinkedDeleted = false,
  });

  final int? id;
  final String? date;
  final String? time;
  final int? callerId;
  final int? equipmentId;
  final String? callerText;
  final String? phoneText;
  final String? departmentText;
  final String? equipmentText;
  final String? issue;
  final String? solution;
  final String? category;
  final int? categoryId;
  final String? status;
  final int? duration;
  final int? isPriority;
  final String? lansweeperState;
  final String? lansweeperMainTicketId;
  final String? lansweeperLastSyncAt;
  final bool isDeleted;

  /// Η συνδεδεμένη εγγραφή users είναι soft-deleted (ιστορική αλήθεια).
  final bool callerLinkedDeleted;

  /// Η συνδεδεμένη εγγραφή equipment είναι soft-deleted.
  final bool equipmentLinkedDeleted;

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      id: map['id'] as int?,
      date: map['date'] as String?,
      time: map['time'] as String?,
      callerId: map['caller_id'] as int?,
      equipmentId: map['equipment_id'] as int?,
      callerText: map['caller_text'] as String?,
      phoneText: map['phone_text'] as String?,
      departmentText: map['department_text'] as String?,
      equipmentText: map['equipment_text'] as String?,
      issue: map['issue'] as String?,
      solution: map['solution'] as String?,
      category: map['category'] as String? ?? map['category_text'] as String?,
      categoryId: map['category_id'] as int?,
      status: map['status'] as String?,
      duration: map['duration'] as int?,
      isPriority: map['is_priority'] as int?,
      lansweeperState: map['lansweeper_state'] as String?,
      lansweeperMainTicketId: map['lansweeper_main_ticket_id'] as String?,
      lansweeperLastSyncAt: map['lansweeper_last_sync_at'] as String?,
      isDeleted: (map['is_deleted'] as int?) == 1,
      callerLinkedDeleted:
          historyEntityIsDeleted(map['caller_is_deleted']),
      equipmentLinkedDeleted:
          historyEntityIsDeleted(map['equipment_is_deleted']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (time != null) 'time': time,
      if (callerId != null) 'caller_id': callerId,
      if (equipmentId != null) 'equipment_id': equipmentId,
      if (callerText != null) 'caller_text': callerText,
      if (phoneText != null) 'phone_text': phoneText,
      if (departmentText != null) 'department_text': departmentText,
      if (equipmentText != null) 'equipment_text': equipmentText,
      if (issue != null) 'issue': issue,
      if (solution != null) 'solution': solution,
      if (category != null) 'category_text': category,
      if (categoryId != null) 'category_id': categoryId,
      if (status != null) 'status': status,
      if (duration != null) 'duration': duration,
      if (isPriority != null) 'is_priority': isPriority,
      if (lansweeperState != null) 'lansweeper_state': lansweeperState,
      if (lansweeperMainTicketId != null)
        'lansweeper_main_ticket_id': lansweeperMainTicketId,
      if (lansweeperLastSyncAt != null)
        'lansweeper_last_sync_at': lansweeperLastSyncAt,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }
}
