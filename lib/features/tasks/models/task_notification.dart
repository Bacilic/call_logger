/// Τι συνέβη σε μια εκκρεμότητα που κατέχει κάποιος άλλος.
///
/// Η ανάθεση και η αφαίρεσή της είναι **η ίδια πράξη με αντίθετη φορά** — γι'
/// αυτό ζουν στον ίδιο κατάλογο και όχι σε δύο μηχανισμούς.
enum TaskNotificationKind {
  /// Κάποιος μου ανέθεσε εκκρεμότητα.
  assigned('assigned'),

  /// Κάποιος μου πήρε εκκρεμότητα που ήταν δική μου.
  unassigned('unassigned'),

  /// Κάποιος έκλεισε εκκρεμότητα που κατείχα.
  closed('closed');

  const TaskNotificationKind(this.dbValue);

  /// Η τιμή όπως γράφεται στη βάση — σταθερή, ανεξάρτητη από το όνομα του
  /// στοιχείου: μια μετονομασία στον κώδικα δεν επιτρέπεται να ακυρώσει
  /// ειδοποιήσεις που περιμένουν ήδη γραμμένες.
  final String dbValue;

  /// Άγνωστη τιμή σημαίνει «γράφτηκε από νεότερη έκδοση»: αγνοείται αντί να
  /// ρίξει την ανάγνωση ολόκληρη.
  static TaskNotificationKind? fromDbValue(String? value) {
    for (final kind in values) {
      if (kind.dbValue == value) return kind;
    }
    return null;
  }
}

/// Μία ειδοποίηση έτοιμη να δειχτεί: τι έγινε, σε ποια εκκρεμότητα, από ποιον.
///
/// Ο **τίτλος** και το **όνομα** δεν αποθηκεύονται μαζί της — έρχονται από τους
/// πίνακες τους τη στιγμή της ανάγνωσης, ώστε μια μετονομασία να μη δείχνει
/// παλιό κείμενο σε ειδοποίηση που δεν έχει ακόμη ιδωθεί.
class TaskNotification {
  const TaskNotification({
    required this.id,
    required this.taskId,
    required this.kind,
    required this.taskTitle,
    required this.createdAt,
    this.actorOperatorId,
  });

  final int id;
  final int taskId;
  final TaskNotificationKind kind;
  final String taskTitle;
  final DateTime? createdAt;

  /// Ποιος το έκανε· `null` όταν η πράξη έγινε χωρίς αναγνωρισμένο χειριστή.
  final int? actorOperatorId;

  static TaskNotification? fromMap(Map<String, dynamic> map) {
    final id = map['id'] as int?;
    final taskId = map['task_id'] as int?;
    final kind = TaskNotificationKind.fromDbValue(map['kind'] as String?);
    if (id == null || taskId == null || kind == null) return null;
    return TaskNotification(
      id: id,
      taskId: taskId,
      kind: kind,
      taskTitle: (map['title'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? ''),
      actorOperatorId: map['actor_operator_id'] as int?,
    );
  }
}
