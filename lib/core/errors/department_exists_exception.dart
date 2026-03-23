/// Ρίχνεται από το data layer όταν αποτυγχάνει εισαγωγή τμήματος λόγω διπλότυπου ονόματος.
/// Το UI διακρίνει: [isDeleted] true = υπάρχει soft-deleted εγγραφή (επιλογή επαναφοράς),
/// false = υπάρχει ήδη ενεργό τμήμα (νέο διακριτό όνομα).
class DepartmentExistsException implements Exception {
  DepartmentExistsException({required this.isDeleted});

  final bool isDeleted;

  @override
  String toString() =>
      'DepartmentExistsException(isDeleted: $isDeleted)';
}
