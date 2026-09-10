// Όποιος δανείζεται τα πεδία της κλήσης, δανείζεται ΜΟΝΟ τα πεδία.
//
// Τα πεδία Τηλέφωνο/Καλών/Τμήμα/Εξοπλισμός είναι ένα κοινό widget. Όπου κι αν
// σταθεί, γράφει στις επιβεβαιώσεις πεδίων και στο μάνταλο μεγάλης προβολής
// **της οθόνης Κλήσεων** — γι' αυτό κάθε φόρμα που τα φιλοξενεί χωρίς να ΕΙΝΑΙ
// η οθόνη Κλήσεων οφείλει να ανοίγει μέσα σε `IsolatedCallsScreenState`.
//
// Χωρίς αυτό, η διόρθωση μιας περσινής κλήσης ή η συμπλήρωση μιας εκκρεμότητας
// άλλαζε την εικόνα της ανοιχτής κλήσης: κάρτες που εξαφανίζονταν, μεγάλη
// προβολή που άνοιγε μόνη της. Το τεστ πιάνει και τον ΕΠΟΜΕΝΟ φιλοξενητή, που
// κανένα τεστ συμπεριφοράς δεν θα πρόσεχε ότι λείπει.
//
//   flutter test test/architecture/calls_fields_isolated_outside_calls_screen_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../test_reporter.dart';

/// Το αρχείο που ΟΡΙΖΕΙ το widget — δεν το φιλοξενεί.
const String _definitionFile = 'smart_entity_selector_widget.dart';

/// Η ίδια η οθόνη Κλήσεων: εκεί η κατάσταση ΕΙΝΑΙ δική της, χωρίς απομόνωση.
const String _theCallsScreenItself = 'call_header_form.dart';

final _hostPattern = RegExp(r'\bSmartEntitySelectorWidget\s*\(');
final _isolationPattern = RegExp(r'\bIsolatedCallsScreenState\b');

Iterable<File> _dartFiles(Directory root) sync* {
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

void main() {
  test('κάθε φόρμα εκτός των Κλήσεων απομονώνει την κατάσταση της οθόνης', () {
    final lib = Directory(p.join(Directory.current.path, 'lib'));
    expect(lib.existsSync(), isTrue, reason: 'Ο φάκελος lib πρέπει να υπάρχει');

    final unguarded = <String>[];
    for (final file in _dartFiles(lib)) {
      final name = p.basename(file.path);
      if (name == _definitionFile || name == _theCallsScreenItself) continue;

      final source = file.readAsStringSync();
      if (!_hostPattern.hasMatch(source)) continue;
      if (_isolationPattern.hasMatch(source)) continue;
      unguarded.add(p.relative(file.path, from: Directory.current.path));
    }

    expect(
      unguarded,
      isEmpty,
      reason: greekExpectMsg(
        'Αυτές οι φόρμες φιλοξενούν τα πεδία της κλήσης χωρίς να απομονώνουν '
        'την κατάσταση της οθόνης Κλήσεων: ${unguarded.join(', ')}. '
        'Τύλιξε τον διάλογο σε IsolatedCallsScreenState.',
      ),
    );
  });
}
