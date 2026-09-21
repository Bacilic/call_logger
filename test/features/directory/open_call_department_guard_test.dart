// Πότε η ανοιχτή κλήση «αφορά» ένα τμήμα που πάει να διαγραφεί.
//
// Ο δρόμος του φαρμακείου: μια διαγραφή τμήματος ενώ έτρεχε κλήση περνούσε
// αθόρυβα, γιατί ο φρουρός υπήρχε μόνο για εξοπλισμό και υπαλλήλους.
//
//   flutter test test/features/directory/open_call_department_guard_test.dart

import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/bulk_department_action_call_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DepartmentModel _dept(int id, String name) =>
    DepartmentModel(id: id, name: name);

/// Στήνει την οθόνη με έναν `WidgetRef` και τρέχει τον έλεγχο πάνω του.
Future<bool> _involves(
  WidgetTester tester, {
  required void Function(SmartEntitySelectorNotifier n) openCall,
  required List<DepartmentModel> selected,
}) async {
  late bool result;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            return TextButton(
              onPressed: () {
                openCall(ref.read(callSmartEntityProvider.notifier));
                result = openCallInvolvesSelectedDepartments(ref, selected);
              },
              child: const Text('έλεγχος'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('έλεγχος'));
  await tester.pump();
  return result;
}

void main() {
  group('Η ανοιχτή κλήση αφορά το τμήμα;', () {
    testWidgets('επιλεγμένο τμήμα της κλήσης → ΝΑΙ', (tester) async {
      final involves = await _involves(
        tester,
        openCall: (n) => n.updateDepartmentText('Φαρμακείο'),
        selected: [_dept(7, 'Φαρμακείο')],
      );

      expect(involves, isTrue);
    });

    testWidgets('γραμμένο όνομα χωρίς κεφαλαία/κενά → ΝΑΙ', (tester) async {
      final involves = await _involves(
        tester,
        openCall: (n) => n.updateDepartmentText('  ΦΑΡΜΑΚΕΙΟ  '),
        selected: [_dept(7, 'Φαρμακείο')],
      );

      expect(
        involves,
        isTrue,
        reason:
            'Το τμήμα μπορεί να έχει πληκτρολογηθεί και να μην έχει κουμπώσει '
            'ακόμη — η κλήση το αφορά εξίσου.',
      );
    });

    testWidgets('άλλο τμήμα → ΟΧΙ', (tester) async {
      final involves = await _involves(
        tester,
        openCall: (n) => n.updateDepartmentText('Αιμοδοσία'),
        selected: [_dept(7, 'Φαρμακείο')],
      );

      expect(involves, isFalse);
    });

    testWidgets('άδεια φόρμα κλήσης → ΟΧΙ, ό,τι κι αν διαγράφεται', (
      tester,
    ) async {
      final involves = await _involves(
        tester,
        openCall: (_) {},
        selected: [_dept(7, 'Φαρμακείο')],
      );

      expect(
        involves,
        isFalse,
        reason: 'Χωρίς ανοιχτή κλήση δεν υπάρχει τίποτα να προστατευτεί.',
      );
    });

    testWidgets('καμία επιλογή → ΟΧΙ', (tester) async {
      final involves = await _involves(
        tester,
        openCall: (n) => n.updateDepartmentText('Φαρμακείο'),
        selected: const [],
      );

      expect(involves, isFalse);
    });
  });
}
