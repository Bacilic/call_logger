import '../../features/calls/models/user_model.dart';

/// Ποιοι κάτοχοι ενός εξοπλισμού ανήκουν σε **άλλο** τμήμα από αυτό όπου
/// πάει να δεθεί.
///
/// Ο κανόνας είναι ο ίδιος με τα τηλέφωνα: ίδιος εξοπλισμός σε περισσότερους
/// υπαλλήλους του **ίδιου** τμήματος επιτρέπεται (βάρδια)· σε διαφορετικά
/// τμήματα όχι. Όποιος επιστρέφεται εδώ πρέπει να ρωτηθεί πριν δεθεί ο
/// εξοπλισμός αλλού — με «Ναι» ο εξοπλισμός φεύγει από αυτόν.
///
/// Το [targetDepartmentId] είναι το τμήμα του νέου κατόχου **μετά** την
/// καταχώρηση· `null` (νέο ή άγνωστο τμήμα) κάνει ξένο κάθε κάτοχο με τμήμα.
/// Κάτοχος χωρίς τμήμα δεν κρίνεται: δεν ξέρουμε πού ανήκει.
List<UserModel> equipmentOwnersInOtherDepartments({
  required Iterable<UserModel> owners,
  required int? newOwnerId,
  required int? targetDepartmentId,
}) {
  return [
    for (final owner in owners)
      if (owner.id != newOwnerId &&
          owner.departmentId != null &&
          owner.departmentId != targetDepartmentId)
        owner,
  ];
}
