/// Επελυμένα ονόματα αναφορών (π.χ. τμημάτων, εργαλείων) για φιλική εμφάνιση audit.
class AuditReferenceLabels {
  const AuditReferenceLabels({
    this.departmentNames = const {},
    this.remoteToolNames = const {},
  });

  static const empty = AuditReferenceLabels();

  final Map<int, String> departmentNames;
  final Map<int, String> remoteToolNames;

  String? departmentName(int? id) {
    if (id == null) return null;
    final name = departmentNames[id]?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  String remoteToolName(int id) {
    final name = remoteToolNames[id]?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Εργαλείο #$id';
  }

  AuditReferenceLabels merge(AuditReferenceLabels other) {
    if (other.departmentNames.isEmpty && other.remoteToolNames.isEmpty) {
      return this;
    }
    if (departmentNames.isEmpty && remoteToolNames.isEmpty) return other;
    return AuditReferenceLabels(
      departmentNames: {...departmentNames, ...other.departmentNames},
      remoteToolNames: {...remoteToolNames, ...other.remoteToolNames},
    );
  }
}
