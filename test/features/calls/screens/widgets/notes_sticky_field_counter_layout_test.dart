// Regression: ο μετρητής χαρακτήρων στις Σημειώσεις δεν πρέπει να επικαλύπτει το κείμενο.
//
//   flutter test test/features/calls/screens/widgets/notes_sticky_field_counter_layout_test.dart

import 'package:call_logger/features/calls/screens/widgets/notes_sticky_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_reporter.dart';
import '../../../../test_setup.dart';

/// Κείμενο ~480 χαρακτήρων με αναδιπλώσεις γραμμής ώστε να γεμίσει το πεδίο.
String _longNotesSample() {
  const line = 'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ αβγδεζηθικλμνξοπρστυφχψω 0123456789 ';
  final buffer = StringBuffer();
  while (buffer.length < 480) {
    buffer.writeln(line);
  }
  return buffer.toString().substring(0, 480);
}

Finder _notesTextFieldFinder() {
  return find.descendant(
    of: find.byType(NotesStickyField),
    matching: find.byType(TextField),
  );
}

Finder _characterCounterFinder() {
  return find.descendant(
    of: find.byType(NotesStickyField),
    matching: find.textContaining('/ 500'),
  );
}

Future<void> _pumpNotesStickyField(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: callLoggerTestProviderOverrides(),
      child: const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: NotesStickyField(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('NotesStickyField · μετρητής χαρακτήρων', () {
    testWidgets(
      'ο μετρητής δεν επικαλύπτει το κείμενο όταν το πεδίο γεμίζει',
      (tester) async {
        await _pumpNotesStickyField(tester);

        final notesField = _notesTextFieldFinder();
        expect(
          notesField,
          findsOneWidget,
          reason: greekExpectMsg('Το πεδίο σημειώσεων πρέπει να εμφανίζεται'),
        );

        await tester.tap(notesField);
        await tester.pumpAndSettle();
        await tester.enterText(notesField, _longNotesSample());
        await tester.pumpAndSettle();

        expect(
          _characterCounterFinder(),
          findsOneWidget,
          reason: greekExpectMsg('Ο μετρητής «N / 500» πρέπει να είναι ορατός'),
        );

        final fieldRect = tester.getRect(notesField);
        final counterRect = tester.getRect(_characterCounterFinder());

        expect(
          counterRect.top,
          greaterThanOrEqualTo(fieldRect.bottom - 1),
          reason: greekExpectMsg(
            'Το πάνω όριο του μετρητή πρέπει να βρίσκεται κάτω από το κάτω '
            'όριο του πεδίου κειμένου (χωρίς επικάλυψη)',
          ),
        );
      },
    );
  });
}
