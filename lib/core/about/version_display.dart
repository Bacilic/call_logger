/// Εμφάνιση έκδοσης χωρίς ειδική ετικέτα προ-έκδοσης.
library;

/// Τίτλος παραθύρου: δείχνει μόνο το version (παραγωγική λειτουργία).
String windowTitleWithVersionLabel(String version) {
  return 'Καταγραφή Κλήσεων v$version';
}

/// Τίτλος παραθύρου όταν τρέχει CLI προφίλ (`--profile`).
String windowTitleWithProfileLabel(String profileName) {
  return 'Καταγραφή Κλήσεων [Profile: ${profileName.trim()}]';
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
String versionChipTooltip(
  String version, {
  String? availableUpdateVersion,
}) {
  final base = 'Ιστορικό αλλαγών — v$version';
  final update = availableUpdateVersion?.trim();
  if (update == null || update.isEmpty) return base;
  return '$base\nΔιαθέσιμη νέα έκδοση $update';
}

/// Υπότιτλος στο διάλογο ιστορικού.
String changelogSubtitleAppLine(String version) {
  return 'Καταγραφή Κλήσεων v$version';
}
