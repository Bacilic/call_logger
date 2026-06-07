import 'package:path/path.dart' as p;

/// Μέγιστο μήκος ονόματος αρχείου (Windows).
const int kWindowsMaxFileNameLength = 255;

const String _forbiddenFileNameChars = r'\/:*?"<>|';

const Set<String> _reservedWindowsBaseNames = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

/// Κανονικοποίηση επέκτασης εικόνας (`.jpeg` → `.jpg`, default `.png`).
String normalizeImageFileExtension(String extension) {
  var ext = extension.trim().toLowerCase();
  if (ext.isEmpty || ext == '.') return '.png';
  if (!ext.startsWith('.')) ext = '.$ext';
  if (ext == '.jpeg') return '.jpg';
  return ext;
}

/// Επιστρέφει μήνυμα σφάλματος ή `null` αν το όνομα είναι έγκυρο για Windows.
String? validateWindowsFileName(String fileName) {
  final trimmed = fileName.trim();
  if (trimmed.isEmpty) {
    return 'Το όνομα δεν μπορεί να είναι κενό.';
  }
  if (trimmed.length > kWindowsMaxFileNameLength) {
    return 'Το όνομα δεν μπορεί να υπερβαίνει τα $kWindowsMaxFileNameLength χαρακτήρες.';
  }
  if (trimmed.endsWith('.') || trimmed.endsWith(' ')) {
    return 'Το όνομα δεν μπορεί να τελειώνει με κενό ή τελεία.';
  }
  for (final unit in trimmed.runes) {
    final ch = String.fromCharCode(unit);
    if (_forbiddenFileNameChars.contains(ch)) {
      return 'Το όνομα περιέχει μη επιτρεπτούς χαρακτήρες (\\ / : * ? " < > |).';
    }
  }

  final base = p.basename(trimmed);
  if (base.isEmpty || base == '.' || base == '..') {
    return 'Μη έγκυρο όνομα αρχείου.';
  }

  final stem = p.basenameWithoutExtension(base);
  if (stem.isEmpty) {
    return 'Το όνομα πρέπει να περιέχει τουλάχιστον έναν χαρακτήρα πριν την κατάληξη.';
  }
  if (stem.endsWith(' ') || stem.endsWith('.')) {
    return 'Το όνομα δεν μπορεί να τελειώνει με κενό ή τελεία.';
  }
  if (_reservedWindowsBaseNames.contains(stem.toUpperCase())) {
    return 'Το όνομα «$stem» είναι δεσμευμένο στα Windows.';
  }

  return null;
}

/// Συνθέτει τελικό όνομα αρχείου, προσθέτοντας [originalExtension] αν λείπει κατάληξη.
String resolveImageTargetFileName({
  required String userInput,
  required String originalExtension,
}) {
  final input = userInput.trim();
  final ext = normalizeImageFileExtension(originalExtension);
  if (p.extension(input).isEmpty) {
    return '$input$ext';
  }
  return input;
}
