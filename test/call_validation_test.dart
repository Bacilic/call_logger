// Widget tests: edge cases / unhappy paths εγκυρότητας φόρμας κλήσεων.
//
// Το πεδίο τηλεφώνου έχει digitsOnly· το '210-LAB' δεν μπορεί να μπει με enterText.
// Κάνουμε enterText στο ίδιο πεδίο (έγκυρα ψηφία) και μετά updatePhone('210-LAB')
// για να εξομοιώσουμε άκυρη τιμή (π.χ. επικόλληση / φόρτωση κατάστασης).
//
//   flutter test test/call_validation_test.dart

import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/calls_screen.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'test_reporter.dart';
import 'test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  final report = GreekTestReportCollector();

  group('Έλεγχοι Εγκυρότητας Φόρμας Κλήσεων (Unhappy Paths)', () {
    setUpAll(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await seedTestCallRowForHistorySearch();
    });

    testWidgets(
      'Μη αριθμητικοί χαρακτήρες στο τηλέφωνο κρατούν το κουμπί υποβολής ανενεργό',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        report.logStep('Φόρτωση εφαρμογής με απομονωμένη βάση');
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

        expect(
          find.byType(NavigationRail),
          findsOneWidget,
          reason: greekExpectMsg('Κύριο κέλυφος / οθόνη Κλήσεων'),
        );

        expect(
          find.byType(CallsScreen),
          findsOneWidget,
          reason: greekExpectMsg('Οθόνη Κλήσεων για πρόσβαση στο callHeaderProvider'),
        );

        final phoneField = callLoggerPhoneTextField();
        expect(
          phoneField,
          findsOneWidget,
          reason: greekExpectMsg('Πεδίο εσωτερικού τηλεφώνου (CallHeaderForm)'),
        );

        report.logStep('Πληκτρολόγηση στο πεδίο τηλεφώνου (έγκυρα ψηφία seed)');
        await tester.tap(phoneField);
        await pumpUntilSettled(tester);
        await tester.enterText(phoneField, kTestPhoneDigits);
        await pumpUntilSettled(tester);

        report.logStep(
          'Ορισμός 210-LAB στο provider (άκυρο για υποβολή· δεν περνάει από digitsOnly πεδίο)',
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(CallsScreen)),
        );
        container.read(callHeaderProvider.notifier).updatePhone('210-LAB');
        await tester.pump();
        await pumpUntilSettled(tester);

        final submitFinder =
            find.widgetWithText(ElevatedButton, 'Καταγραφή');
        expect(
          submitFinder,
          findsOneWidget,
          reason: greekExpectMsg('Κουμπί υποβολής οθόνης Κλήσεων'),
        );

        final btn = tester.widget<ElevatedButton>(submitFinder);
        expect(
          btn.onPressed,
          isNull,
          reason: greekExpectMsg(
            'Με γράμματα στο εσωτερικό το canSubmitCall πρέπει να κρατά το κουμπί απενεργοποιημένο',
          ),
        );
        report.logStep('Επιβεβαιώθηκε απενεργοποιημένο κουμπί για 210-LAB');
      },
      semanticsEnabled: false,
    );
  });

  tearDownAll(() {
    report.printFinalSummary(
      title: 'Συγκεντρωτική αναφορά call_validation_test (ελληνικά)',
    );
  });
}
