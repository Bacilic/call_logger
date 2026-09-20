// Κάθε διάλογος μαζικής επεξεργασίας του Καταλόγου ρωτά για την ανοιχτή κλήση.
//
// Ο φρουρός υπήρχε για υπαλλήλους και εξοπλισμό, αλλά όχι για τμήματα — και η
// ασυμμετρία δεν φαινόταν πουθενά: κάθε διάλογος ήταν σωστός «μόνος του». Ο
// έλεγχος διαβάζει τον πηγαίο κώδικα, γιατί ακριβώς αυτό λείπει όταν ένας νέος
// διάλογος γραφτεί κατ' εικόνα των υπολοίπων και ξεχάσει τη μία γραμμή.
//
//   flutter test test/architecture/open_call_guard_covers_every_bulk_dialog_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Οι διάλογοι μαζικής επεξεργασίας, με τον φρουρό που οφείλει να καλεί ο
/// καθένας.
const Map<String, String> _bulkDialogGuards = {
  'bulk_user_edit_dialog.dart': 'ensureBulkUserActionAllowed',
  'bulk_equipment_edit_dialog.dart': 'ensureBulkEquipmentActionAllowed',
  'bulk_department_edit_dialog.dart': 'ensureBulkDepartmentActionAllowed',
};

void main() {
  const dir = 'lib/features/directory/screens/widgets';

  test('κάθε διάλογος μαζικής επεξεργασίας καλεί τον φρουρό του', () {
    final missing = <String>[];

    for (final entry in _bulkDialogGuards.entries) {
      final file = File(p.join(dir, entry.key));
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Ο διάλογος «${entry.key}» μετακινήθηκε ή μετονομάστηκε — ο έλεγχος '
            'δείχνει σε αρχείο που δεν υπάρχει και θα περνούσε ψευδώς.',
      );
      if (!file.readAsStringSync().contains(entry.value)) {
        missing.add('${entry.key} → ${entry.value}');
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'Διάλογοι χωρίς φρουρό ανοιχτής κλήσης: $missing. Χωρίς αυτόν, μια '
          'μαζική αλλαγή πάνω σε οντότητα που συμμετέχει στην κλήση που τρέχει '
          'περνά αθόρυβα.',
    );
  });

  test('όλοι οι φρουροί μοιράζονται τον ίδιο διάλογο', () {
    final guards = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith('_action_call_guard.dart'))
        .toList();

    expect(
      guards.length,
      _bulkDialogGuards.length,
      reason: 'Ένας φρουρός ανά οντότητα — ούτε λιγότεροι ούτε περισσότεροι.',
    );

    for (final guard in guards) {
      expect(
        guard.readAsStringSync(),
        contains('ensureOpenCallAllowsCatalogAction'),
        reason:
            'Ο «${p.basename(guard.path)}» έφτιαξε δικό του διάλογο αντί να '
            'χρησιμοποιήσει τον κοινό — από εκεί ξεκινά η απόκλιση.',
      );
    }
  });
}
