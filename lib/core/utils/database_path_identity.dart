import 'dart:io';

import 'package:path/path.dart' as p;

/// Συγκρίνει αν δύο διαδρομές δείχνουν στο ίδιο αρχείο βάσης
/// (κανονικοποίηση + χωρίς διάκριση πεζών-κεφαλαίων στα Windows).
bool databasePathsReferToSameFile(String a, String b) {
  final na = p.normalize(a);
  final nb = p.normalize(b);
  if (Platform.isWindows) {
    return na.toLowerCase() == nb.toLowerCase();
  }
  return na == nb;
}
