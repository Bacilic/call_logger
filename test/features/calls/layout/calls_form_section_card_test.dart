// Widget tests: τα στοιχεία φόρμας (σημειώσεις, κατηγορία/εκκρεμότητα)
// ντύνονται σε κοινή SectionCard «Στοιχεία κλήσης» — όχι «γυμνά» στοιχεία.
//
//   flutter test test/features/calls/layout/calls_form_section_card_test.dart

import 'package:call_logger/core/widgets/section_card.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
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

  group('φόρμα κλήσης — ντύσιμο σε SectionCard', () {
    testWidgets(
      'σημειώσεις και κατηγορία/εκκρεμότητα μέσα σε κοινή κάρτα «Στοιχεία κλήσης»',
      (tester) async {
        await _pumpExpandedCallsScreen(tester);

        expect(find.byType(NotesStickyField), findsOneWidget);
        expect(find.byType(CategoryAutocompleteField), findsOneWidget);

        expect(
          find.ancestor(
            of: find.byType(NotesStickyField),
            matching: find.byType(SectionCard),
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Οι σημειώσεις πρέπει να φιλοξενούνται σε SectionCard',
          ),
        );
        expect(
          find.ancestor(
            of: find.byType(CategoryAutocompleteField),
            matching: find.byType(SectionCard),
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Η κατηγορία/εκκρεμότητα πρέπει να φιλοξενείται σε SectionCard',
          ),
        );

        // Κοινή κάρτα: το SectionCard των σημειώσεων περιέχει και την κατηγορία.
        final sharedCard = find.ancestor(
          of: find.byType(NotesStickyField),
          matching: find.byType(SectionCard),
        );
        expect(
          find.descendant(
            of: sharedCard,
            matching: find.byType(CategoryAutocompleteField),
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Σημειώσεις και κατηγορία πρέπει να μοιράζονται την ίδια κάρτα',
          ),
        );

        expect(
          find.text('Στοιχεία κλήσης'),
          findsOneWidget,
          reason: greekExpectMsg('Ο τίτλος της κάρτας πρέπει να εμφανίζεται'),
        );
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
