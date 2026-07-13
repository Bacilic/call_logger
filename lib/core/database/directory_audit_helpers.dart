/// Σταθερή ενέργεια audit για συσχέτιση από κλήση.
const String kAuditCallAssociationAction = 'συσχέτιση από κλήση';

const String _kLegacyCallAssociationActionPrefix = 'συσχέτιση από κλήση:';

/// Χωριστή ενέργεια και γραμμή λεπτομερειών για νέες εγγραφές «συσχέτιση από κλήση».
({String action, String? detailsLine}) buildAuditCallAssociationEntry({
  String? userPart,
  String? departmentPart,
  String? phonePart,
  String? equipmentPart,
}) {
  final parts = <String>[];
  for (final p in [userPart, departmentPart, phonePart, equipmentPart]) {
    final t = p?.trim() ?? '';
    if (t.isNotEmpty) parts.add(t);
  }
  return (
    action: kAuditCallAssociationAction,
    detailsLine: parts.isEmpty ? null : parts.join(' - '),
  );
}

/// Προτάσσει τα μέρη συσχέτισης στις λεπτομέρειες audit (χωρίς απώλεια υπάρχοντος κειμένου).
String mergeAuditCallAssociationDetails({
  String? associationDetails,
  String? existingDetails,
}) {
  final assoc = associationDetails?.trim();
  final exist = existingDetails?.trim();
  if (assoc == null || assoc.isEmpty) {
    return exist ?? '';
  }
  if (exist == null || exist.isEmpty) {
    return assoc;
  }
  return '$assoc · $exist';
}

/// Κανονικοποίηση παλιάς γραμμής audit με ουρά στην ενέργεια (idempotent).
({String action, String? details})? normalizeLegacyCallAssociationAuditRow({
  required String action,
  String? details,
}) {
  final trimmed = action.trim();
  if (trimmed == kAuditCallAssociationAction) {
    return null;
  }
  if (!trimmed.startsWith(_kLegacyCallAssociationActionPrefix)) {
    return null;
  }
  final tail =
      trimmed.substring(_kLegacyCallAssociationActionPrefix.length).trim();
  final merged = mergeAuditCallAssociationDetails(
    associationDetails: tail.isEmpty ? null : tail,
    existingDetails: details,
  );
  return (
    action: kAuditCallAssociationAction,
    details: merged.isEmpty ? null : merged,
  );
}
