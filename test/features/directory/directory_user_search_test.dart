// Widget test: αναζήτηση χρήστη στην καρτέλα Χρήστες του Καταλόγου (μετά από seed).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/directory_user_search_test.dart

import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Αναζήτηση Καταλόγου — Χρήστες (widget)', () {
    setUpAll(() async {
      await seedTestCallRowForHistorySearch();
    });

    // Καρτέλα Κατάλογος → Χρήστες, αναζήτηση με kTestUserFirstName, εμφάνιση στον πίνακα.
    //   flutter test test/features/directory/directory_user_search_test.dart --plain-name "Κατάλογος: αναζήτηση χρήστη με το όνομα του seed"
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
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
