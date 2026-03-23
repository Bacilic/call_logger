/// Κοινό επίθεμα εμφάνισης για soft-deleted τμήματα (χρήστες / εξοπλισμός / lookup).
const String kDepartmentDeletedDisplaySuffix = ' (Διεγραμμένο)';

/// Αφαιρεί το [kDepartmentDeletedDisplaySuffix] από κείμενο που προήλθε από εμφάνιση lookup.
String stripDepartmentDeletedDisplaySuffix(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return '';
  if (t.endsWith(kDepartmentDeletedDisplaySuffix)) {
    return t
        .substring(0, t.length - kDepartmentDeletedDisplaySuffix.length)
        .trim();
  }
  return t;
}
