// Widget test: αναζήτηση στην οθόνη Ιστορικού (μετά από seed κλήσης).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/history/history_search_test.dart

import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Αναζήτηση Ιστορικού (widget)', () {
    setUpAll(() async {
      await seedTestCallRowForHistorySearch();
    });

    // Μετάβαση στο Ιστορικό, αναζήτηση με marker seed — εμφάνιση γραμμής στον πίνακα.
    //   flutter test test/features/history/history_search_test.dart --plain-name "Ιστορικό: φίλτρο κειμένου εμφανίζει τη δοκιμαστική κλήση"
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
        // Χρονοδιακόπτες sqflite (κλείδωμα ~10s) — αποφυγή pending timers στο tearDown.
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
