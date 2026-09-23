import 'dart:io';

import 'package:path/path.dart' as p;

/// Επιστρέφει φάκελο για `FilePicker` `initialDirectory` (desktop).
///
/// Σειρά: αν υπάρχει αρχείο → φάκελος του· αν υπάρχει φάκελος → αυτός·
/// ανάβασμα γονέων μέχρι πρώτο υπάρχοντα κατάλογο· τελευταία λύση `C:\`.
///
/// Ο επιλογέας των Windows δέχεται μόνο διαδρομή που ξεκινά από γράμμα δίσκου
/// ή από `\\διακομιστή\κοινόχρηστο`. Σε οτιδήποτε άλλο (π.χ. `.` από κείμενο
/// σαν «POPINIO\φάκελος», ή `\Windows`) πετά «Η παράμετρος είναι εσφαλμένη»
/// και η εξαίρεση ρίχνει ολόκληρη την εφαρμογή — γι' αυτό τέτοιο κείμενο
/// πέφτει κατευθείαν στο `C:\`.
String? initialDirectoryForFilePicker(String? pathHint) {
  const fallback = r'C:\';
  // Κάθετοι → ανάποδες πριν από κάθε άλλη πράξη: με κάθετους το `p.normalize`
  // κόβει τη μία από τις δύο αρχικές ενός `//διακομιστής/κοινόχρηστο`.
  final raw = (pathHint?.trim() ?? '').replaceAll('/', r'\');
  if (!_shellRoot.hasMatch(raw)) {
    return fallback;
  }
  try {
    final f = File(raw);
    if (f.existsSync()) {
      final t = f.statSync().type;
      if (t == FileSystemEntityType.file) {
        return p.normalize(p.dirname(raw));
      }
      if (t == FileSystemEntityType.directory) {
        return p.normalize(raw);
      }
    }
    final d = Directory(raw);
    if (d.existsSync()) {
      return p.normalize(raw);
    }
    var dir = p.dirname(raw);
    for (var i = 0; i < 32; i++) {
      if (dir.isEmpty || dir == raw) break;
      final tryDir = Directory(dir);
      if (tryDir.existsSync()) {
        return p.normalize(dir);
      }
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
  } catch (_) {}
  return fallback;
}

/// `X:\…` ή `\\διακομιστής\κοινόχρηστο…` — οι μόνες μορφές που ανοίγει ο
/// επιλογέας των Windows.
final RegExp _shellRoot = RegExp(r'^([A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)');
