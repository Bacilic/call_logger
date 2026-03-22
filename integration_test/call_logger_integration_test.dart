// ============================================================================
// integration_test / call_logger_integration_test.dart
// ============================================================================
//
// ΣΚΟΠΟΣ
// -------
// Αυτό είναι **ολοκληρωμένη δοκιμή (integration test)** στο επίπεδο Flutter:
// φορτώνει την πραγματική εφαρμογή ([MyApp]) μέσα στο harness του
// `integration_test`, με **ίδια** (ή πολύ κοντινή) συμπεριφορά με την εκτέλεση
// σε συσκευή/επιτραπέζιο — σε αντίθεση με τα unit/widget tests στο `test/`
// που τρέχουν συνήθως στο VM χωρίς πλήρες εκτελέσιμο.
//
// ΤΙ ΕΛΕΓΧΕΙ ΣΥΓΚΕΚΡΙΜΑ ΑΥΤΟ ΤΟ ΑΡΧΕΙΟ
// ----------------------------------------
// 1. **Εκκίνηση UI**: `pumpWidget` με [ProviderScope] και τα overrides της
//    `callLoggerTestProviderOverrides()` ώστε η εφαρμογή να χρησιμοποιεί
//    **απομονωμένη βάση δοκιμών** (όχι την παραγωγική)· η δέσμευση γίνεται
//    μέσω `registerCallLoggerIsolatedDatabaseHooksIntegration()` στο `test_setup`.
// 2. **Σταθεροποίηση frames**: `pumpUntilSettledLong` / `pumpUntilSettled` από
//    `test_setup` (όχι απεριόριστο `pumpAndSettle`, λόγω χρονομέτρου κλήσης κ.λπ.).
// 3. **Έλεγχος κύριας οθόνης**: `expect` ότι εμφανίζεται το κείμενο
//    «Καταγραφή Κλήσεων» (τίτλος AppBar).
// 4. **Πλοήγηση (NavigationRail + Ρυθμίσεις)**: με `semanticsEnabled: false`, διαδοχικά
//    Ιστορικό, Κατάλογο (καρτέλα «Χρήστες»), Εκκρεμότητες, Βάση Δεδομένων, push
//    Ρυθμίσεις από AppBar (`tooltip` «Ρυθμίσεις»), `pageBack`, επιστροφή σε Κλήσεις
//    (`nav_rail_calls`). Τα κλειδιά rail: `main_shell.dart`.
//
// ΑΝΑΦΟΡΑ ΣΤΑ ΕΛΛΗΝΙΚΑ (GreekTestReportCollector)
// ----------------------------------------------
// Τα `logStep` τυπώνουν βήματα στο τερματικό. Το `tearDownAll` καλεί
// `printFinalSummary`: αυτή η σύνοψη μετράει **μόνο** ρητές κλήσεις
// `recordPass` / `recordFail` — **όχι** το τελικό pass/fail του Flutter runner.
// Το πραγματικό αποτέλεσμα είναι οι γραμμές `+N -M` και τυχόν `[E]` πιο πάνω.
//
// ΕΝΤΟΛΕΣ ΕΚΤΕΛΕΣΗΣ (αντιγραφή από τη ρίζα του project call_logger)
// -----------------------------------------------------------------
// Βασική (VM / προεπιλογή ανά περιβάλλον):
//
//   flutter test integration_test/call_logger_integration_test.dart
//
// Σε Windows desktop συχνά χρειάζεται ρητά το προφίλ συσκευής:
//
//   flutter test integration_test/call_logger_integration_test.dart -d windows
//
// Μόνο αυτό το σενάριο (όνομα ομάδας/δοκιμής — χρήσιμο για επανάληψη):
//
//   flutter test integration_test/call_logger_integration_test.dart -d windows --plain-name "Ολοκληρωμένες ροές (integration_test) Εκκίνηση εφαρμογής και εμφάνιση κύριας οθόνης Κλήσεων"
//
// ============================================================================

import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/test_reporter.dart';
import '../test/test_setup.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final report = GreekTestReportCollector();
  registerCallLoggerIsolatedDatabaseHooksIntegration();

  group('Ολοκληρωμένες ροές (integration_test)', () {
    testWidgets(
      'Εκκίνηση εφαρμογής και εμφάνιση κύριας οθόνης Κλήσεων',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        report.logStep('Έναρξη integration: φόρτωση MyApp με απομονωμένη βάση');
        await tester.pumpWidget(
          ProviderScope(
            overrides: callLoggerTestProviderOverrides(),
            child: const MyApp(),
          ),
        );
        await tester.pump();
        await pumpUntilSettledLong(tester);

        expect(
          find.text('Καταγραφή Κλήσεων'),
          findsOneWidget,
          reason: greekExpectMsg('Τίτλος AppBar κύριας εφαρμογής'),
        );

        report.logStep('Πλοήγηση στο Ιστορικό (NavigationRail)');
        await tester.tap(find.byKey(const ValueKey('nav_rail_history')));
        await pumpUntilSettled(tester);

        expect(
          find.text('Ιστορικό Κλήσεων'),
          findsOneWidget,
          reason: greekExpectMsg('Πλοήγηση στο Ιστορικό μέσω NavigationRail'),
        );

        report.logStep('Πλοήγηση στον Κατάλογο (NavigationRail)');
        await tester.tap(find.byKey(const ValueKey('nav_rail_directory')));
        await pumpUntilSettled(tester);
        expect(
          find.text('Χρήστες'),
          findsOneWidget,
          reason: greekExpectMsg(
            'Οθόνη Καταλόγου: καρτέλα TabBar (ο τίτλος AppBar είναι κρυφός)',
          ),
        );

        report.logStep('Πλοήγηση στις Εκκρεμότητες (NavigationRail)');
        await tester.tap(find.byKey(const ValueKey('nav_rail_tasks')));
        await pumpUntilSettled(tester);
        expect(
          find.text('Εκκρεμότητες'),
          findsAtLeastNWidgets(1),
          reason: greekExpectMsg(
            'Οθόνη Εκκρεμοτήτων (AppBar + ετικέτα NavigationRail όταν extended)',
          ),
        );

        report.logStep('Πλοήγηση στη Βάση Δεδομένων (NavigationRail)');
        await tester.tap(find.byKey(const ValueKey('nav_rail_database')));
        await pumpUntilSettled(tester);
        expect(
          find.text('Πάτα για προεπισκόπηση'),
          findsAtLeastNWidgets(1),
          reason: greekExpectMsg(
            'Λίστα πινάκων DatabaseBrowser (υπότιτλος ListTile — απομονωμένη βάση με πίνακες)',
          ),
        );

        report.logStep('Άνοιγμα Ρυθμίσεων (AppBar, όχι NavigationRail)');
        await tester.tap(find.byTooltip('Ρυθμίσεις'));
        await pumpUntilSettled(tester);
        expect(
          find.text('Ρυθμίσεις'),
          findsOneWidget,
          reason: greekExpectMsg('Τίτλος AppBar οθόνης Ρυθμίσεων'),
        );

        report.logStep('Κλείσιμο Ρυθμίσεων και επιστροφή στο κέλυφος');
        // `pageBack()` αναζητά CupertinoNavigationBarBackButton· σε Material (Windows)
        // χρησιμοποιούμε το κουμπί οπισθοδρόμησης του AppBar.
        await tester.tap(find.byIcon(Icons.arrow_back));
        await pumpUntilSettled(tester);

        report.logStep('Πλοήγηση πίσω στις Κλήσεις (NavigationRail)');
        await tester.tap(find.byKey(const ValueKey('nav_rail_calls')));
        await pumpUntilSettled(tester);
        expect(
          find.text('Καταγραφή Κλήσεων'),
          findsOneWidget,
          reason: greekExpectMsg('Επιστροφή στην αρχική οθόνη Κλήσεων'),
        );

        // Δεν καλούμε recordPass εδώ: το testWidgets μπορεί να αποτύχει *μετά* το τέλος
        // του σώματος (π.χ. pending timers / invariants), οπότε η ελληνική αναφορά
        // θα έδειχνε ψευδώς «όλα OK» ενώ ο runner εμφανίζει [E].
        report.logStep(
          'Ολοκληρώθηκαν τα βήματα ροής (έλεγχος επιτυχίας = γραμμές +N -M πιο πάνω)',
        );
      },
      semanticsEnabled: false,
    );
  });

  tearDownAll(() {
    report.printFinalSummary(
      title: 'Συγκεντρωτική αναφορά integration_test (ελληνικά)',
    );
  });
}
