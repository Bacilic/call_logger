// Κάθε μήνυμα με κουμπί ενέργειας δηλώνει ρητά αν φεύγει μόνο του.
//
// Το Flutter 3.47 βαφτίζει «μόνιμο» κάθε `SnackBar` που έχει `action`, χωρίς
// να το ζητήσει κανείς (`persist = persist ?? action != null`). Ο
// χρονομετρητής τρέχει κανονικά, αλλά όταν λήξει ο `ScaffoldMessenger`
// γυρίζει πίσω χωρίς να κλείσει τίποτα. Το μήνυμα κάθεται στην οθόνη — και,
// χειρότερα, μπλοκάρει την ουρά, οπότε κανένα επόμενο δεν εμφανίζεται ποτέ.
//
// Ο κανόνας που φυλάει αυτό το τεστ: όποιος βάζει κουμπί ενέργειας αποφασίζει
// ο ίδιος τη διάρκεια ζωής. Καμία σιωπηλή προεπιλογή του framework δεν
// αποφασίζει για τη διεπαφή μας — και η επόμενη αλλαγή γνώμης του Flutter
// βγαίνει εδώ σε κόκκινο τεστ, όχι στην οθόνη του χρήστη.
//
//   flutter test test/architecture/snackbar_lifetime_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _snackBarStart = RegExp(r'\bSnackBar\s*\(');
final _actionPattern = RegExp(r'\bSnackBarAction\s*\(');
final _persistPattern = RegExp(r'\bpersist\s*:');

Iterable<File> _dartFiles(Directory root) sync* {
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

/// Το αρχείο με τις γραμμές σχολίων σβησμένες, ώστε να μη μετρηθούν
/// παρενθέσεις μέσα σε επεξηγήσεις. Οι αριθμοί γραμμών διατηρούνται.
String _withoutCommentLines(String source) {
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('//')) lines[i] = '';
  }
  return lines.join('\n');
}

/// Το κείμενο της κλήσης που ξεκινά στην ανοιχτή παρένθεση [openIndex], με
/// ισοστάθμιση παρενθέσεων. `null` όταν η κλήση δεν κλείνει (δεν συμβαίνει σε
/// κώδικα που μεταγλωττίζεται).
String? _callBody(String source, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < source.length; i++) {
    final char = source[i];
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return source.substring(openIndex, i + 1);
    }
  }
  return null;
}

int _lineOf(String source, int index) =>
    '\n'.allMatches(source.substring(0, index)).length + 1;

void main() {
  test('Κάθε SnackBar με κουμπί ενέργειας δηλώνει ρητά τη διάρκεια ζωής του', () {
    final projectRoot = Directory.current;
    final libRoot = Directory(p.join(projectRoot.path, 'lib'));
    expect(
      libRoot.existsSync(),
      isTrue,
      reason: 'Αναμένεται φάκελος lib/ στο root του project.',
    );

    final violations = <String>[];

    for (final file in _dartFiles(libRoot)) {
      final source = _withoutCommentLines(file.readAsStringSync());
      if (!_actionPattern.hasMatch(source)) continue;

      final relative = p
          .relative(file.path, from: projectRoot.path)
          .replaceAll(r'\', '/');

      for (final match in _snackBarStart.allMatches(source)) {
        final openIndex = source.indexOf('(', match.start);
        final body = _callBody(source, openIndex);
        if (body == null) continue;
        if (!_actionPattern.hasMatch(body)) continue;
        if (_persistPattern.hasMatch(body)) continue;

        violations.add(
          '$relative:${_lineOf(source, match.start)} — SnackBar με '
          'SnackBarAction χωρίς ρητό persist',
        );
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Βρέθηκαν ${violations.length} μηνύματα με κουμπί ενέργειας που '
        'αφήνουν το Flutter να αποφασίσει τη διάρκεια ζωής τους.\n'
        'Δήλωσε ρητά «persist: false» (φεύγει μόνο του) ή «persist: true» '
        '(μένει ώσπου να το κλείσει κάποιος):\n'
        '${violations.join('\n')}',
      );
    }
  });
}
