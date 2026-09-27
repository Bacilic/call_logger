// Η καρτέλα «Επεξεργασία κλήσης» δεν σβήνει πεδία που δεν διαχειρίζεται.
//
//   flutter test test/features/history/call_edit_keeps_untouched_fields_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

/// Τα πεδία της κλήσης που καταλήγουν στη βάση σε κάθε ενημέρωση.
///
/// Διαβάζονται από τον ίδιο τον χάρτη εγγραφής αντί να γραφτούν με το χέρι: μια
/// καρφωτή λίστα θα έμενε πίσω ακριβώς τη μέρα που θα προστεθεί νέο πεδίο — που
/// είναι η μέρα που χρειάζεται ο φρουρός.
Map<String, String> _persistedColumnToProperty() {
  final source = File(
    'lib/core/database/calls_repository.dart',
  ).readAsStringSync();
  final start = source.indexOf('Map<String, dynamic> _callWriteMap(');
  expect(start, greaterThan(-1), reason: 'Ο χάρτης εγγραφής μετακόμισε.');
  final end = source.indexOf('\n  }', start);
  final body = source.substring(start, end);
  // Η αντιστοίχιση διαβάζεται, δεν μαντεύεται: το `category` ζει στη στήλη
  // `category_text`, και ένας κανόνας μετατροπής ονομάτων θα έβγαζε ψεύτικο
  // εύρημα ακριβώς εκεί.
  final pairs = RegExp(r"'(\w+)':\s*call\.(\w+)").allMatches(body);
  final map = {for (final m in pairs) m.group(1)!: m.group(2)!};
  expect(map, isNotEmpty, reason: 'Δεν διαβάστηκε καμία στήλη εγγραφής.');
  return map;
}

Set<String> _persistedProperties() =>
    _persistedColumnToProperty().values.toSet();

/// Το μπλοκ που χτίζει την ενημερωμένη κλήση μέσα στην καρτέλα.
String _editDialogUpdateBlock() {
  final source = File(
    'lib/features/history/widgets/call_edit_dialog.dart',
  ).readAsStringSync();
  final start = source.indexOf('final updated = CallModel(');
  expect(start, greaterThan(-1), reason: 'Η κατασκευή της κλήσης μετακόμισε.');
  final end = source.indexOf('\n    );', start);
  return source.substring(start, end);
}

/// Οι στήλες που ζητά ρητά το ερώτημα της αναφοράς/ταμπλό.
Set<String> _dashboardSelectedColumns() {
  final source = File(
    'lib/core/database/calls_dashboard_repository.dart',
  ).readAsStringSync();
  final start = source.indexOf('SELECT\n        calls.id,');
  expect(start, greaterThan(-1), reason: 'Το ερώτημα του ταμπλό μετακόμισε.');
  final end = source.indexOf('FROM calls', start);
  final body = source.substring(start, end);
  return {
    ...RegExp(r'calls\.(\w+)').allMatches(body).map((m) => m.group(1)!),
    // Στήλες που έρχονται από έκφραση με ψευδώνυμο, π.χ. το caller_text.
    ...RegExp(r'AS (\w+)').allMatches(body).map((m) => m.group(1)!),
  };
}

void main() {
  test('το ερώτημα της αναφοράς διαβάζει κάθε στήλη που γράφεται', () {
    // Ο τίτλος της #18 γραφόταν σωστά στη βάση και φαινόταν στο γρήγορο
    // ιστορικό εξοπλισμού — αλλά η Αναφορά Lansweeper έδειχνε τον αυτόματο,
    // επειδή το ερώτημά της απαριθμεί ρητά τις στήλες και τον είχε ξεχάσει.
    // Η στήλη υπήρχε, η τιμή υπήρχε· απλώς δεν ταξίδευε ως εκεί.
    final selected = _dashboardSelectedColumns();
    final missing = [
      for (final column in _persistedColumnToProperty().keys)
        if (!selected.contains(column)) column,
    ]..sort();

    expect(
      missing,
      isEmpty,
      reason: greekExpectMsg(
        'Στήλες που γράφονται αλλά δεν διαβάζονται από την αναφορά — η φόρμα '
        'θα τις βλέπει πάντα κενές: ${missing.join(', ')}',
      ),
    );
  });

  test('κάθε πεδίο που γράφεται στη βάση το δίνει και η καρτέλα', () {
    // Το πικρό παράδειγμα: ο τίτλος της κλήσης #18, γραμμένος από τη φόρμα
    // Lansweeper, μηδενιζόταν σε κάθε αποθήκευση της καρτέλας — επειδή η
    // καρτέλα χτίζει νέο αντικείμενο απαριθμώντας ρητά τα πεδία, και το
    // ξέχασε. Δεν υπάρχει καν πεδίο τίτλου εκεί για να το δει ο χειριστής.
    //
    // Όποιο πεδίο δεν επεξεργάζεται η καρτέλα ακολουθεί το πρωτότυπο· κανένα
    // δεν επιτρέπεται να λείπει και να γραφτεί σιωπηλά ως κενό.
    final block = _editDialogUpdateBlock();
    final missing = [
      for (final property in _persistedProperties())
        if (!RegExp('\\b$property:').hasMatch(block)) property,
    ]..sort();

    expect(
      missing,
      isEmpty,
      reason: greekExpectMsg(
        'Πεδία που γράφονται στη βάση αλλά λείπουν από την καρτέλα — θα '
        'μηδενιστούν σε κάθε αποθήκευση: ${missing.join(', ')}',
      ),
    );
  });
}
