// Widget tests: κανόνες φόρμας κλήσης.
//
// ΚΑΝΟΝΑΣ 1: Οι σημειώσεις είναι αυτόνομο «χαρτί» — ΔΕΝ ντύνονται με
//   κάρτα/τίτλο («Στοιχεία κλήσης» δεν υπάρχει πουθενά).
// ΚΑΝΟΝΑΣ 2: Το τικ «Εκκρεμότητα» ζει ΜΟΝΙΜΑ μέσα στο χαρτί σημειώσεων.
// ΚΑΝΟΝΑΣ 3: Κατηγορία + χρονόμετρο + «Καταγραφή» = ίδια γραμμή (ένα widget).
//
//   flutter test test/features/calls/layout/calls_form_rules_test.dart

import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/call_status_bar.dart';
import 'package:call_logger/features/calls/screens/widgets/category_autocomplete_field.dart';
import 'package:call_logger/features/calls/screens/widgets/notes_sticky_field.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../test_reporter.dart';
import '../../../test_setup.dart';

Future<void> _pumpExpandedCallsScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(2000, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: callLoggerTestProviderOverrides(),
        child: const MyApp(),
      ),
    );
    await tester.pump();
    await pumpUntilSettledLong(tester);
    await GoogleFonts.pendingFonts();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(lookupServiceProvider.future);
  });

  final phoneField = callLoggerPhoneTextField();
  await tester.tap(phoneField);
  await pumpUntilSettled(tester);
  await tester.enterText(phoneField, kTestPhoneDigits);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilSettled(tester, steps: 40, step: const Duration(milliseconds: 60));
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('κανόνες φόρμας κλήσης', () {
    testWidgets(
      'το τικ Εκκρεμότητα ζει μέσα στο χαρτί σημειώσεων — χωρίς κάρτα-τίτλο',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);

        expect(find.byType(NotesStickyField), findsOneWidget);

        // ΚΑΝΟΝΑΣ 2: τικ + ετικέτα μέσα στο post-it.
        expect(
          find.descendant(
            of: find.byType(NotesStickyField),
            matching: find.byType(Checkbox),
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το τικ Εκκρεμότητας πρέπει να βρίσκεται μέσα στο χαρτί σημειώσεων',
          ),
        );
        expect(
          find.descendant(
            of: find.byType(NotesStickyField),
            matching: find.text('Εκκρεμότητα'),
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Η ετικέτα «Εκκρεμότητα» πρέπει να βρίσκεται μέσα στο χαρτί',
          ),
        );

        // ΚΑΝΟΝΑΣ 1: το χαρτί δεν ντύνεται με κάρτα-τίτλο.
        expect(
          find.text('Στοιχεία κλήσης'),
          findsNothing,
          reason: greekExpectMsg(
            'Οι σημειώσεις είναι αυτόνομο χαρτί — καμία κάρτα «Στοιχεία κλήσης»',
          ),
        );
        expect(
          find.ancestor(
            of: find.byType(NotesStickyField),
            matching: find.byType(Card),
          ),
          findsNothing,
          reason: greekExpectMsg(
            'Το χαρτί σημειώσεων δεν πρέπει να φιλοξενείται μέσα σε Card',
          ),
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'με άδειες σημειώσεις το τικ Εκκρεμότητας είναι ανενεργό',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);

        final checkbox = tester.widget<Checkbox>(
          find.descendant(
            of: find.byType(NotesStickyField),
            matching: find.byType(Checkbox),
          ),
        );
        expect(
          checkbox.onChanged,
          isNull,
          reason: greekExpectMsg(
            'Χωρίς σημειώσεις δεν επιτρέπεται εκκρεμότητα (τικ ανενεργό)',
          ),
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'κατηγορία, χρονόμετρο και Καταγραφή μοιράζονται την ίδια γραμμή',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);

        expect(find.byType(CategoryAutocompleteField), findsOneWidget);

        // ΚΑΝΟΝΑΣ 3: χρονόμετρο (CallStatusBar) και κουμπί «Καταγραφή»
        // κατοικούν στο ίδιο widget γραμμής με την κατηγορία.
        final rowFinder = find.ancestor(
          of: find.byType(CategoryAutocompleteField),
          matching: find.byType(Row),
        );
        expect(rowFinder, findsWidgets);

        final sharedRow = rowFinder.first;
        expect(
          find.descendant(
            of: sharedRow,
            matching: find.byType(CallStatusBar),
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το χρονόμετρο πρέπει να είναι στην ίδια γραμμή με την κατηγορία',
          ),
        );
        expect(
          find.descendant(
            of: sharedRow,
            matching: find.widgetWithText(ElevatedButton, 'Καταγραφή'),
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το κουμπί «Καταγραφή» πρέπει να είναι στην ίδια γραμμή με την κατηγορία',
          ),
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
