import 'dart:io';

import 'package:path/path.dart' as p;

/// Επιστρέφει φάκελο για `FilePicker` `initialDirectory` (desktop).
///
/// Σειρά: αν υπάρχει αρχείο → φάκελος του· αν υπάρχει φάκελος → αυτός·
/// ανάβασμα γονέων μέχρι πρώτο υπάρχοντα κατάλογο· τελευταία λύση `C:\`.
String? initialDirectoryForFilePicker(String? pathHint) {
  final raw = pathHint?.trim() ?? '';
  if (raw.isEmpty) {
    return r'C:\';
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
  return r'C:\';
}
