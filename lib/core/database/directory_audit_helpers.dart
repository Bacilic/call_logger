/// Κείμενο ενέργειας «συσχέτιση από κλήση: μέρος1 - μέρος2 …» (παραλείπονται κενά).
String auditCallAssociationActionLine({
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
  if (parts.isEmpty) return 'συσχέτιση από κλήση';
  return 'συσχέτιση από κλήση: ${parts.join(' - ')}';
}
