/// Εμφάνιση έκδοσης: προ-έκδοση (βήτα) όταν το major είναι 0 (SemVer 0.x.y).
library;

/// True αν η συμβολοσειρά έκδοσης είναι της μορφής 0.x.y (προ-έκδοση / beta track).
bool isBetaTrackVersion(String version) {
  final first = version.split(RegExp(r'[-+]')).first.trim();
  final majorStr = first.split('.').first;
  final major = int.tryParse(majorStr);
  return major == 0;
}

/// Τίτλος παραθύρου: προσθέτει «βήτα» για έκδοση 0.x.y.
String windowTitleWithVersionLabel(String version) {
  final core = 'Καταγραφή Κλήσεων v$version';
  if (isBetaTrackVersion(version)) {
    return '$core βήτα';
  }
  return core;
}

/// Κείμενο chip: συμπαγής ή πλήρης ετικέτα με ένδειξη βήτα όταν major = 0.
String versionChipLabel(String version, {required bool extended}) {
  final beta = isBetaTrackVersion(version);
  if (extended) {
    final base = 'v$version';
    return beta ? '$base βήτα' : base;
  }
  final parts = version.split(RegExp(r'[-+]')).first.trim().split('.');
  final short = parts.length >= 2 ? '${parts[0]}.${parts[1]}' : version;
  final base = 'v$short';
  return beta ? '$base β' : base;
}

/// Tooltip για το chip έκδοσης.
String versionChipTooltip(String version) {
  if (isBetaTrackVersion(version)) {
    return 'Ιστορικό αλλαγών — έκδοση βήτα v$version';
  }
  return 'Ιστορικό αλλαγών — v$version';
}

/// Υπότιτλος στο διάλογο ιστορικού (χωρίς επανάληψη «Καταγραφή Κλήσεων» αν χρειάζεται πλήρες).
String changelogSubtitleAppLine(String version) {
  final core = 'Καταγραφή Κλήσεων v$version';
  if (isBetaTrackVersion(version)) {
    return '$core βήτα';
  }
  return core;
}
