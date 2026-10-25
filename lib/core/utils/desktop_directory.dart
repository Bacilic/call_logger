import 'dart:io';

import 'package:path/path.dart' as p;

/// Η Επιφάνεια εργασίας του χρήστη, αν υπάρχει εκεί που την περιμένουμε —
/// η προτεινόμενη θέση των εξαγωγών. `null`: ο διάλογος αποθήκευσης ανοίγει
/// όπου θέλει τα Windows.
String? desktopDirectory() {
  final profile = Platform.environment['USERPROFILE'];
  if (profile == null || profile.isEmpty) return null;
  for (final candidate in [
    p.join(profile, 'Desktop'),
    p.join(profile, 'OneDrive', 'Desktop'),
  ]) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  return null;
}
