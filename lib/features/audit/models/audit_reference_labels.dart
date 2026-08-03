/// Επελυμένα ονόματα αναφορών (π.χ. τμημάτων, χρηστών, εργαλείων) για φιλική εμφάνιση audit.
class AuditReferenceLabels {
  const AuditReferenceLabels({
    this.departmentNames = const {},
    this.remoteToolNames = const {},
    this.userNames = const {},
  });

  static const empty = AuditReferenceLabels();

  final Map<int, String> departmentNames;
  final Map<int, String> remoteToolNames;
  final Map<int, String> userNames;

  String? departmentName(int? id) {
    if (id == null) return null;
    final name = departmentNames[id]?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  String? userName(int? id) {
    if (id == null) return null;
    final name = userNames[id]?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  String remoteToolName(int id) {
    final name = remoteToolNames[id]?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Εργαλείο #$id';
  }

  AuditReferenceLabels merge(AuditReferenceLabels other) {
    if (other.departmentNames.isEmpty &&
        other.remoteToolNames.isEmpty &&
        other.userNames.isEmpty) {
      return this;
    }
    if (departmentNames.isEmpty &&
        remoteToolNames.isEmpty &&
        userNames.isEmpty) {
      return other;
    }
    return AuditReferenceLabels(
      departmentNames: {...departmentNames, ...other.departmentNames},
      remoteToolNames: {...remoteToolNames, ...other.remoteToolNames},
      userNames: {...userNames, ...other.userNames},
    );
  }
}
