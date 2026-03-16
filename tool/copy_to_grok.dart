// ignore_for_file: avoid_print

import 'dart:io';

/// Script που αντιγράφει συγκεκριμένα αρχεία στο φάκελο Grok.
/// Δέχεται ονόματα αρχείων ή paths (χωρισμένα με κόμμα).
/// Path: χρήση απευθείας. Όνομα αρχείου: αναδρομική αναζήτηση σε lib/ και root.
///
/// Παράδειγμα: dart run tool/copy_to_grok.dart main.dart,lib/features/tasks/models/task.dart
void main(List<String> arguments) {
  try {
    // Ρίζα του project (υποθέτουμε ότι τρέχουμε από το root)
    final projectRoot = Directory.current;
    final grokDir = Directory('${projectRoot.path}${Platform.pathSeparator}Grok');
    final sep = Platform.pathSeparator;

    // 1. Επαναφορά/δημιουργία φακέλου Grok
    _prepareGrokDirectory(grokDir);

    // 2. Ανάλυση ορισμάτων: ονόματα αρχείων ή paths χωρισμένα με κόμμα
    final items = _parseItems(arguments);
    if (items.isEmpty) {
      print('Δεν δόθηκαν αρχεία. Χρήση: dart run tool/copy_to_grok.dart file1.dart,lib/path/to/file2.dart');
      exit(1);
    }

    // 3. Αντιγραφή: path → απευθείας, όνομα αρχείου → αναδρομική αναζήτηση
    final libDir = Directory('${projectRoot.path}$sep''lib');
    for (final item in items) {
      final bool isPath = _isPath(item);
      File? found;
      String destFilename = item;

      if (isPath) {
        // Path: σχετικό από το root του project (και από lib/ αν δεν υπάρχει στο root)
        final normalized = item.replaceAll('/', sep);
        final candidates = [
          '${projectRoot.path}$sep$normalized',
          '${projectRoot.path}$sep''lib$sep$normalized',
        ];
        for (final p in candidates) {
          final file = File(p);
          if (file.existsSync()) {
            found = file;
            destFilename = file.uri.pathSegments.last;
            break;
          }
        }
      }
      if (found == null) {
        // Fallback: αναζήτηση με βάση μόνο το όνομα αρχείου (τελευταίο segment)
        final basename = item.contains('/') || item.contains('\\')
            ? item.replaceAll('\\', '/').split('/').last
            : item;
        found = _findFileRecursively(libDir, basename) ?? _findFileRecursively(projectRoot, basename);
      }

      if (found != null) {
        final dest = File('${grokDir.path}$sep$destFilename');
        found.copySync(dest.path);
        print('Αντιγράφηκε: ${found.path} -> ${dest.path}');
      } else {
        print('ΠΡΟΕΙΔΟΠΟΙΗΣΗ: Δεν βρέθηκε το αρχείο "$item" (αναζήτηση σε lib/ και root).');
      }
    }
  } on IOException catch (e) {
    print('Σφάλμα I/O: $e');
    exit(1);
  } catch (e, st) {
    print('Σφάλμα: $e');
    print(st);
    exit(1);
  }
}

/// Διαγράφει πλήρως τα περιεχόμενα του Grok ή δημιουργεί τον φάκελο αν δεν υπάρχει.
void _prepareGrokDirectory(Directory grokDir) {
  if (grokDir.existsSync()) {
    grokDir.deleteSync(recursive: true);
  }
  grokDir.createSync(recursive: true);
}

/// Επιστρέφει true αν το [item] είναι path (περιέχει / ή \).
bool _isPath(String item) => item.contains('/') || item.contains('\\');

/// Παίρνει τα ορίσματα και επιστρέφει λίστα στοιχείων (paths ή ονόματα αρχείων, χωρισμένα με κόμμα).
List<String> _parseItems(List<String> arguments) {
  if (arguments.isEmpty) return [];
  final singleString = arguments.join(',');
  return singleString
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Αναδρομική αναζήτηση για αρχείο με συγκεκριμένο όνομα μέσα σε [dir].
/// Επιστρέφει το πρώτο File που ταιριάζει ή null.
File? _findFileRecursively(Directory dir, String filename) {
  if (!dir.existsSync()) return null;
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File) {
        if (entity.path.endsWith(filename) || entity.uri.pathSegments.last == filename) {
          return entity;
        }
      } else if (entity is Directory) {
        final found = _findFileRecursively(entity, filename);
        if (found != null) return found;
      }
    }
  } on IOException {
    return null;
  }
  return null;
}
