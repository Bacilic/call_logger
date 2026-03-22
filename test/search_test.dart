// Widget tests: αναζήτηση στο Ιστορικό και στον Κατάλογο χρηστών (μετά από seed κλήσης).
//
// Ολόκληρο αρχείο:
//   flutter test test/search_test.dart
// Ομάδα (και τα δύο τεστ ιστορικού/καταλόγου):
//   flutter test test/search_test.dart --plain-name "Αναζήτηση Ιστορικού και Καταλόγου (widget)"

import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_reporter.dart';
import 'test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Αναζήτηση Ιστορικού και Καταλόγου (widget)', () {
    setUpAll(() async {
      await seedTestCallRowForHistorySearch();
    });

    // Μετάβαση στο Ιστορικό, αναζήτηση με marker seed — εμφάνιση γραμμής στον πίνακα.
    //   flutter test test/search_test.dart --plain-name "Ιστορικό: φίλτρο κειμένου εμφανίζει τη δοκιμαστική κλήση"
    testWidgets(
      'Ιστορικό: φίλτρο κειμένου εμφανίζει τη δοκιμαστική κλήση',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();
        reporter.logStep('Φόρτωση εφαρμογής για αναζήτηση στο Ιστορικό');

        await tester.pumpWidget(
          ProviderScope(
            overrides: callLoggerTestProviderOverrides(),
            child: const MyApp(),
          ),
        );
        await tester.pump();
        await pumpUntilSettledLong(tester);

        reporter.logStep('Μετάβαση στο Ιστορικό μέσω πλοήγησης');
        await tester.tap(find.byKey(const ValueKey('nav_rail_history')));
        await pumpUntilSettled(tester);

        expect(
          find.text('Ιστορικό Κλήσεων'),
          findsOneWidget,
          reason: greekExpectMsg('Μετάβαση στην οθόνη Ιστορικού'),
        );

        final searchField = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText?.contains('Αναζήτηση') ?? false),
        );
        expect(
          searchField,
          findsOneWidget,
          reason: greekExpectMsg('Πεδίο αναζήτησης ιστορικού'),
        );
        reporter.logStep('Εισαγωγή κειμένου αναζήτησης στο Ιστορικό');
        await tester.tap(searchField);
        await pumpUntilSettled(tester);
        await tester.enterText(searchField, kTestHistorySearchMarker);
        await pumpUntilSettled(tester);

        expect(
          find.textContaining(kTestHistorySearchMarker),
          findsWidgets,
          reason: greekExpectMsg('Ο πίνακας ιστορικού πρέπει να εμφανίζει το σημείο αναζήτησης'),
        );
        reporter.recordPass('Αναζήτηση στο Ιστορικό');
      },
      semanticsEnabled: false,
    );

    // Καρτέλα Κατάλογος → Χρήστες, αναζήτηση με kTestUserFirstName, εμφάνιση στον πίνακα.
    //   flutter test test/search_test.dart --plain-name "Κατάλογος: αναζήτηση χρήστη με το όνομα του seed"
    testWidgets(
      'Κατάλογος: αναζήτηση χρήστη με το όνομα του seed',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();
        reporter.logStep('Φόρτωση εφαρμογής για αναζήτηση στον Κατάλογο');

        await tester.pumpWidget(
          ProviderScope(
            overrides: callLoggerTestProviderOverrides(),
            child: const MyApp(),
          ),
        );
        await tester.pump();
        await pumpUntilSettledLong(tester);

        reporter.logStep('Μετάβαση στον Κατάλογο (Χρήστες)');
        await tester.tap(find.byKey(const ValueKey('nav_rail_directory')));
        await pumpUntilSettled(tester);

        final userSearch = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText?.contains('Όνομα') ?? false),
        );
        expect(
          userSearch,
          findsOneWidget,
          reason: greekExpectMsg('Πεδίο αναζήτησης καρτέλας Χρήστες'),
        );
        reporter.logStep('Αναζήτηση με το όνομα χρήστη του seed');
        await tester.tap(userSearch);
        await pumpUntilSettled(tester);
        await tester.enterText(userSearch, kTestUserFirstName);
        await pumpUntilSettled(tester);

        expect(
          find.textContaining(kTestUserFirstName),
          findsWidgets,
          reason: greekExpectMsg('Ο πίνακας πρέπει να εμφανίζει το όνομα χρήστη από το seed'),
        );
        reporter.recordPass('Αναζήτηση στον Κατάλογο (Χρήστες)');
      },
      semanticsEnabled: false,
    );
  });
}
