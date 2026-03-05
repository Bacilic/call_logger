/// Μοντέλο κλήσης (πίνακας calls).
class CallModel {
  CallModel({
    this.id,
    this.date,
    this.time,
    this.callerId,
    this.equipmentId,
    this.issue,
    this.solution,
    this.category,
    this.status,
    this.duration,
    this.isPriority,
  });

  final int? id;
  final String? date;
  final String? time;
  final int? callerId;
  final int? equipmentId;
  final String? issue;
  final String? solution;
  final String? category;
  final String? status;
  final int? duration;
  final int? isPriority;

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      id: map['id'] as int?,
      date: map['date'] as String?,
      time: map['time'] as String?,
      callerId: map['caller_id'] as int?,
      equipmentId: map['equipment_id'] as int?,
      issue: map['issue'] as String?,
      solution: map['solution'] as String?,
      category: map['category'] as String?,
      status: map['status'] as String?,
      duration: map['duration'] as int?,
      isPriority: map['is_priority'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (time != null) 'time': time,
      if (callerId != null) 'caller_id': callerId,
      if (equipmentId != null) 'equipment_id': equipmentId,
      if (issue != null) 'issue': issue,
      if (solution != null) 'solution': solution,
      if (category != null) 'category': category,
      if (status != null) 'status': status,
      if (duration != null) 'duration': duration,
      if (isPriority != null) 'is_priority': isPriority,
    };
  }
}
