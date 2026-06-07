/// Επελυμένα ονόματα αναφορών (π.χ. τμημάτων) για φιλική εμφάνιση audit.
class AuditReferenceLabels {
  const AuditReferenceLabels({this.departmentNames = const {}});

  static const empty = AuditReferenceLabels();

  final Map<int, String> departmentNames;

  String? departmentName(int? id) {
    if (id == null) return null;
    final name = departmentNames[id]?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  AuditReferenceLabels merge(AuditReferenceLabels other) {
    if (other.departmentNames.isEmpty) return this;
    if (departmentNames.isEmpty) return other;
    return AuditReferenceLabels(
      departmentNames: {...departmentNames, ...other.departmentNames},
    );
  }
}
