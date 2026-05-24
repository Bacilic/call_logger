/// Αποτυχία αποθήκευσης εκκρεμότητας (συμπεριλαμβανομένου audit) — rollback transaction.
class TaskSaveException implements Exception {
  TaskSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
