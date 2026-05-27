/// Εμφάνιση έκδοσης χωρίς ειδική ετικέτα προ-έκδοσης.
library;

/// Τίτλος παραθύρου: δείχνει μόνο το version.
String windowTitleWithVersionLabel(String version) {
  return 'Καταγραφή Κλήσεων v$version';
}

/// Κείμενο chip: συμπαγής ή πλήρης ετικέτα έκδοσης.
String versionChipLabel(String version, {required bool extended}) {
  if (extended) {
    return 'v$version';
  }
  final parts = version.split(RegExp(r'[-+]')).first.trim().split('.');
  final short = parts.length >= 2 ? '${parts[0]}.${parts[1]}' : version;
  return 'v$short';
}

/// Tooltip για το chip έκδοσης.
String versionChipTooltip(String version) {
  return 'Ιστορικό αλλαγών — v$version';
}

/// Υπότιτλος στο διάλογο ιστορικού.
String changelogSubtitleAppLine(String version) {
  return 'Καταγραφή Κλήσεων v$version';
}
