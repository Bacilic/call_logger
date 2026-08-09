// Πρότυπο αρίθμησης και προεπισκόπηση.
//
// Είκοσι εγγραφές αλλάζουν με ένα κλικ· χωρίς προεπισκόπηση η ενέργεια θα
// ήταν στοίχημα.
//
//   flutter test test/features/lamp/widgets/lamp_serial_series_fields_test.dart

import 'package:call_logger/core/database/old_database/lamp_serial_series.dart';
import 'package:call_logger/features/lamp/widgets/lamp_serial_series_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  const defaultTemplate = 'NLSHR125070-$kLampSeriesCounterToken';

  Future<TextEditingController> pump(
    WidgetTester tester, {
    String custom = '',
    List<int> codes = const <int>[3818, 3819, 3822, 3830, 3831],
    List<String> taken = const <String>[],
  }) async {
    final controller = TextEditingController(text: custom);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LampSerialSeriesFields(
            buildPlan: (template) => lampBuildSerialSeries(
              template: template,
              equipmentCodes: codes,
              takenSerials: taken,
            ),
            defaultTemplate: defaultTemplate,
            controller: controller,
            descriptionByCode: const <int, String>{
              3818: 'HANDHELD BARCODE SCANNER',
            },
            onUseDefault: controller.clear,
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('η προεπιλογή δείχνει το αποτέλεσμα, όχι το πρότυπο', (
    tester,
  ) async {
    await pump(tester);

    expect(
      find.widgetWithText(ChoiceChip, 'NLSHR125070-1'),
      findsOneWidget,
      reason: greekExpectMsg(
        'Ο χρήστης κρίνει από αυτό που θα γραφτεί, όχι από τον τελεστή',
      ),
    );
    expect(
      find.widgetWithText(ChoiceChip, 'NLSHR125070 (1)'),
      findsNothing,
      reason: greekExpectMsg(
        'Η δεύτερη σταθερή μορφή αφαιρέθηκε — τη θέση της πήρε το '
        'προσαρμοσμένο πεδίο',
      ),
    );
  });

  testWidgets('η προεπισκόπηση δείχνει τι θα γραφτεί και πού', (tester) async {
    await pump(tester);

    expect(find.text('NLSHR125070-1'), findsWidgets);
    expect(
      find.textContaining('3818 · HANDHELD BARCODE SCANNER'),
      findsOneWidget,
    );
    expect(
      find.text('… και 2 ακόμη, με τη σειρά του κωδικού'),
      findsOneWidget,
      reason: greekExpectMsg(
        'Πέντε εγγραφές, τρεις ορατές — ο χρήστης πρέπει να ξέρει ότι '
        'αλλάζουν περισσότερες από όσες βλέπει',
      ),
    );
  });

  testWidgets('προσαρμοσμένο πρότυπο αλλάζει την προεπισκόπηση', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(
      find.byKey(const Key('lamp_series_custom_template')),
      'Πληκτρολόγιο Dell (61)-$kLampSeriesCounterToken',
    );
    await tester.pumpAndSettle();

    expect(find.text('Πληκτρολόγιο Dell (61)-1'), findsOneWidget);
    expect(find.text('Πληκτρολόγιο Dell (61)-2'), findsOneWidget);
  });

  testWidgets('πρότυπο χωρίς τελεστή: κενή προεπισκόπηση και σφάλμα', (
    tester,
  ) async {
    await pump(tester, custom: 'NLSHR125070');

    expect(
      find.byKey(const Key('lamp_series_preview_empty')),
      findsOneWidget,
      reason: greekExpectMsg(
        'Χωρίς τον τελεστή όλες οι εγγραφές θα έπαιρναν την ίδια τιμή — ο '
        'χρήστης πρέπει να το δει πριν πατήσει',
      ),
    );
  });

  testWidgets('η επιστροφή στην προεπιλογή καθαρίζει το πεδίο', (tester) async {
    final controller = await pump(tester, custom: 'ΚΑΤΙ-άλλο');

    await tester.tap(find.byKey(const Key('lamp_series_default_format')));
    await tester.pumpAndSettle();

    expect(controller.text, isEmpty);
    expect(find.text('NLSHR125070-1'), findsWidgets);
  });

  testWidgets('η συνέχεια υπάρχουσας σειράς εμφανίζεται', (tester) async {
    await pump(
      tester,
      codes: const <int>[10],
      taken: <String>[for (var i = 1; i <= 10; i++) 'NLSHR125070-$i'],
    );

    final note = tester.widget<Text>(
      find.byKey(const Key('lamp_series_continuation')),
    );
    expect(note.data, contains('1 έως 10'));
    expect(note.data, contains('συνεχίζει από το 11'));
  });

  testWidgets('χωρίς υπάρχουσα σειρά δεν εμφανίζεται σημείωση', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('lamp_series_continuation')), findsNothing);
  });
}
