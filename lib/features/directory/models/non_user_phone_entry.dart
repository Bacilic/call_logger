/// Γραμμή καταλόγου: τηλέφωνο στη βάση χωρίς καμία εγγραφή σε `user_phones`.
class NonUserPhoneEntry {
  const NonUserPhoneEntry({
    required this.phoneId,
    required this.number,
    this.departmentNamesDisplay,
    this.primaryDepartmentId,
  });

  final int phoneId;
  final String number;
  /// Ονόματα τμημάτων (π.χ. GROUP_CONCAT) ή κενό.
  final String? departmentNamesDisplay;
  /// Ελάχιστο id έγκυρου τμήματος για άνοιγμα φόρμας τμήματος (ή null).
  final int? primaryDepartmentId;

  String get departmentLabel =>
      (departmentNamesDisplay?.trim().isNotEmpty ?? false)
          ? departmentNamesDisplay!.trim()
          : '—';
}
