// ignore_for_file: avoid_print

import 'dart:io';

/// Script που αντιγράφει συγκεκριμένα αρχεία στο φάκελο Grok.
/// Δέχεται ως όρισμα ένα string με ονόματα αρχείων χωρισμένα με κόμμα.
///
/// Παράδειγμα: dart run tool/copy_to_grok.dart main.dart,import_service.dart
void main(List<String> arguments) {
  try {
    // Ρίζα του project (υποθέτουμε ότι τρέχουμε από το root)
    final projectRoot = Directory.current;
    final grokDir = Directory('${projectRoot.path}${Platform.pathSeparator}Grok');

    // 1. Επαναφορά/δημιουργία φακέλου Grok
    _prepareGrokDirectory(grokDir);

    // 2. Ανάλυση ορισμάτων: ένα string με ονόματα αρχείων χωρισμένα με κόμμα
    final filenames = _parseFilenames(arguments);
    if (filenames.isEmpty) {
      print('Δεν δόθηκαν ονόματα αρχείων. Χρήση: dart run tool/copy_to_grok.dart file1.dart,file2.dart');
      exit(1);
    }

    // 3. Αναζήτηση και αντιγραφή κάθε αρχείου
    final libDir = Directory('${projectRoot.path}${Platform.pathSeparator}lib');
    for (final filename in filenames) {
      final found = _findFileRecursively(libDir, filename) ?? _findFileRecursively(projectRoot, filename);
      if (found != null) {
        final dest = File('${grokDir.path}${Platform.pathSeparator}$filename');
        found.copySync(dest.path);
        print('Αντιγράφηκε: ${found.path} -> ${dest.path}');
      } else {
        print('ΠΡΟΕΙΔΟΠΟΙΗΣΗ: Δεν βρέθηκε το αρχείο "$filename" (αναζήτηση σε lib/ και root).');
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

/// Παίρνει τα ορίσματα και επιστρέφει λίστα ονομάτων αρχείων (χωρισμένα με κόμμα).
List<String> _parseFilenames(List<String> arguments) {
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
