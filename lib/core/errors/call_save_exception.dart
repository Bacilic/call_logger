/// Αποτυχία αποθήκευσης κλήσης (συμπεριλαμβανομένου audit) — rollback transaction.
class CallSaveException implements Exception {
  CallSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
