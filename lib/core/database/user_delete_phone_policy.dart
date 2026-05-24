/// Τηλέφωνο που συνδέεται με ακριβώς έναν χρήστη (1↔1) πριν από soft delete.
class ExclusivePhoneForUserDelete {
  const ExclusivePhoneForUserDelete({
    required this.phoneId,
    required this.number,
    required this.userId,
    this.departmentId,
    this.departmentName,
  });

  final int phoneId;
  final String number;
  final int userId;
  final int? departmentId;
  final String? departmentName;
}

/// Επιλογή χρήστη όταν διαγράφεται ο μοναδικός κάτοχος τηλεφώνου.
enum UserDeleteExclusivePhoneAction {
  /// Αποσύνδεση από χρήστη· το νούμερο μένει στο τμήμα του χρήστη (αν υπάρχει).
  keepAtDepartment,

  /// Αποσύνδεση από χρήστη και αφαίρεση από τμήμα / κατάλογο τμήματος.
  removePhone,
}
