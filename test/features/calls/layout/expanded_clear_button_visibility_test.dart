// Regression: «Εκκαθάριση» ορατό σε αναπτυγμένη όψη ανεξάρτητα από ενεργή ομάδα τηλεφώνου.
//
//   flutter test test/features/calls/layout/expanded_clear_button_visibility_test.dart

import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/calls_screen.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../test_reporter.dart';
import '../../../test_setup.dart';

Finder _clearButtonFinder() =>
    find.widgetWithText(OutlinedButton, 'Εκκαθάριση');

Future<void> _pumpCallsExpanded(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 900);
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
}

Future<void> _confirmPhoneField(WidgetTester tester) async {
  final phoneField = callLoggerPhoneTextField();
  await tester.tap(phoneField);
  await pumpUntilSettled(tester);
  await tester.enterText(phoneField, kTestPhoneDigits);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await pumpUntilSettled(tester);
}

Future<ProviderContainer> _callsContainer(WidgetTester tester) {
  return Future.value(
    ProviderScope.containerOf(tester.element(find.byType(CallsScreen))),
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Νέα κλήση · Εκκαθάριση σε αναπτυγμένη όψη', () {
    testWidgets(
      'expanded latch κενά πεδία: το Εκκαθάριση παραμένει προσβάσιμο',
      (tester) async {
        await _pumpCallsExpanded(tester);
        await _confirmPhoneField(tester);

        final container = await _callsContainer(tester);
        expect(
          container.read(callsScreenIsExpandedProvider),
          isTrue,
          reason: greekExpectMsg('Μετά επιβεβαίωση τηλεφώνου → expanded'),
        );

        await tester.tap(find.byTooltip('Καθαρισμός όλων των πεδίων'));
        await pumpUntilSettled(tester);

        expect(
          container.read(callsFieldGroupsProvider).anyGroupActive,
          isFalse,
          reason: greekExpectMsg('Μετά κόκκινο × καμία ενεργή ομάδα'),
        );
        expect(
          container.read(callsScreenIsExpandedProvider),
          isTrue,
          reason: greekExpectMsg('Μετά κόκκινο × η κεφαλίδα μένει expanded'),
        );
        expect(
          _clearButtonFinder(),
          findsOneWidget,
          reason: greekExpectMsg(
            'Αναπτυγμένη όψη χωρίς τηλέφωνο: το Εκκαθάριση πρέπει να είναι ορατό',
          ),
        );

        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'ενεργή ομάδα τηλεφώνου: ένα μόνο κουμπί Εκκαθάριση',
      (tester) async {
        await _pumpCallsExpanded(tester);
        await _confirmPhoneField(tester);

        expect(
          _clearButtonFinder(),
          findsOneWidget,
          reason: greekExpectMsg(
            'Με ενεργή ομάδα τηλεφώνου: ένα Εκκαθάριση στο anchor κάτω δεξιά',
          ),
        );

        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'tap Εκκαθάριση σε expanded latch: επιστροφή σε συμπτυγμένη όψη',
      (tester) async {
        await _pumpCallsExpanded(tester);
        await _confirmPhoneField(tester);

        await tester.tap(find.byTooltip('Καθαρισμός όλων των πεδίων'));
        await pumpUntilSettled(tester);

        final container = await _callsContainer(tester);
        expect(container.read(callsScreenIsExpandedProvider), isTrue);

        await tester.tap(_clearButtonFinder());
        await pumpUntilSettled(tester);
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          container.read(callsScreenIsExpandedProvider),
          isFalse,
          reason: greekExpectMsg('Μετά Εκκαθάριση → συμπτυγμένη όψη'),
        );

        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
