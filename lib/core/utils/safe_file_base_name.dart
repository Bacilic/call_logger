/// Ασφαλές basename αρχείου από κείμενο (χωρίς `\\ / : * ? " < > |`).
///
/// Για ετικέτες ορόφου: κενά/παύλες → `_`, πεζά (π.χ. `1st_floor`, `1ος_γραφεία`).
String safeFileBaseName(String raw, {bool snakeCase = false}) {
  var s = raw.trim();
  if (s.isEmpty) return 'floor_map';
  const forbidden = r'\/:*?"<>|';
  final buf = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (forbidden.contains(c)) {
      buf.write('_');
    } else {
      buf.write(c);
    }
  }
  s = buf.toString();
  if (snakeCase) {
    s = s
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-–—]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    while (s.startsWith('_')) {
      s = s.substring(1);
    }
    while (s.endsWith('_')) {
      s = s.substring(0, s.length - 1);
    }
  } else {
    s = s.replaceAll(RegExp(r'_+'), '_').trim();
  }
  if (s.isEmpty || s == '.') return 'floor_map';
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

/// Basename εικόνας κατόψεως από ετικέτα ορόφου.
String safeFloorImageBaseName(String floorLabel) =>
    safeFileBaseName(floorLabel, snakeCase: true);
