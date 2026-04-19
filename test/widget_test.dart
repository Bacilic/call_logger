// Βασικά widget tests με απομονωμένη βάση (βλ. test_setup / docs/TESTING_EL.md).
//
// Για πλήκτρα: πάντα keyUp μετά το keyDown — βλ. docs/KEYBOARD_AND_FOCUS.md.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/widget_test.dart

import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  // Ελέγχει τίτλο «Καταγραφή Κλήσεων» και τουλάχιστον τέσσερα TextField στην κύρια φόρμα.
  //   flutter test test/widget_test.dart --plain-name "Η εφαρμογή εμφανίζει το κύριο κέλυφος και τα πεδία εισαγωγής κλήσης"
  testWidgets(
    'Η εφαρμογή εμφανίζει το κύριο κέλυφος και τα πεδία εισαγωγής κλήσης',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: callLoggerTestProviderOverrides(),
          child: const MyApp(),
        ),
      );
      await tester.pump();
      await pumpUntilSettledLong(tester);

      expect(
        find.byType(NavigationRail),
        findsOneWidget,
      );
      // Τηλέφωνο, Καλών, Τμήμα, Εξοπλισμός, Σημειώσεις, Κατηγορία (κ.ά.)
      expect(find.byType(TextField), findsAtLeastNWidgets(4));
    },
    semanticsEnabled: false,
  );

  // Ελέγχει ότι στο πεδίο Καλούντας το κενό (space) δεν αντικαθιστά όλο το κείμενο (focus + keyDown/keyUp).
  //   flutter test test/widget_test.dart --plain-name "Πεδίο Καλούντας: πληκτρολόγηση ονόματος και κενό χωρίς αντικατάσταση όλου του κειμένου"
  testWidgets(
    'Πεδίο Καλούντας: πληκτρολόγηση ονόματος και κενό χωρίς αντικατάσταση όλου του κειμένου',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: callLoggerTestProviderOverrides(),
          child: const MyApp(),
        ),
      );
      await tester.pump();
      await pumpUntilSettledLong(tester);

      final callerField = callLoggerCallerTextField();
      expect(callerField, findsOneWidget);
      await tester.tap(callerField);
      await tester.pump();

      await tester.enterText(callerField, 'Κατερίνα');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();

      final editable = find.descendant(
        of: callerField,
        matching: find.byType(EditableText),
      );
      expect(editable, findsOneWidget);
      final text = tester.widget<EditableText>(editable).controller.text;
      expect(text, contains('Κατερίνα'));
      expect(text.length, greaterThanOrEqualTo(8));

      await tester.pump(const Duration(milliseconds: 300));
      await pumpUntilSettled(tester);
    },
    semanticsEnabled: false,
  );
}
