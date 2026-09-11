import '../../features/directory/models/department_kind.dart';

/// Ρίχνεται από το data layer όταν αποτυγχάνει εισαγωγή τμήματος λόγω διπλότυπου ονόματος.
/// Το UI διακρίνει: [isDeleted] true = υπάρχει soft-deleted εγγραφή (επιλογή επαναφοράς),
/// false = υπάρχει ήδη ενεργό τμήμα (νέο διακριτό όνομα).
class DepartmentExistsException implements Exception {
  DepartmentExistsException({
    required this.isDeleted,
    this.kind = DepartmentKind.hospital,
  });

  final bool isDeleted;

  /// Τι είναι η καρτέλα που βρέθηκε — ώστε ο διάλογος να τη λέει με το όνομά
  /// της. Χωρίς αυτό η επαναφορά μιλούσε για «τμήμα» ακόμη και για εταιρεία.
  final DepartmentKind kind;

  @override
  String toString() =>
      'DepartmentExistsException(isDeleted: $isDeleted, kind: ${kind.dbValue})';
}
