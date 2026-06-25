// Widget tests: πλήρης / αρνητική ροή φόρμας κλήσης με απομονωμένη βάση.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/calls/call_form_test.dart
// Ολόκληρη ομάδα «Ροή φόρμας κλήσεων (widget)» (και τα δύο τεστ):
//   flutter test test/features/calls/call_form_test.dart --plain-name "Ροή φόρμας κλήσεων (widget)"

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/calls_dashboard_providers.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/call_status_bar.dart';
import 'package:call_logger/features/calls/screens/widgets/category_autocomplete_field.dart';
import 'package:call_logger/features/calls/screens/widgets/notes_sticky_field.dart';
import 'package:call_logger/features/calls/screens/widgets/global_recent_calls_list.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Ροή φόρμας κλήσεων (widget)', () {
    setUpAll(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await seedTestCallRowForHistorySearch();
      // Επιβολή ανανέωσης της in-memory cache μετά το seeding
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    // Happy path: τηλέφωνο → lookup → κατηγορία/σημειώσεις → υποβολή και έλεγχος εγγραφής στη SQLite.
    //   flutter test test/features/calls/call_form_test.dart --plain-name "Happy path: τηλέφωνο, lookup, πεδία, κατηγορία, σημειώσεις, καταγραφή κλήσης"
    testWidgets(
      'Happy path: τηλέφωνο, lookup, πεδία, κατηγορία, σημειώσεις, καταγραφή κλήσης',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();
        final sw = Stopwatch()..start();

        reporter.logStep('Ξεκινά φόρτωση εφαρμογής με απομονωμένη βάση δοκιμών');
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
          // Το Future του καταλόγου τρέχει πραγματικό async· τα pump μόνα τους δεν
          // ολοκληρώνουν το await loadFromDatabase() πριν βγούμε από το runAsync.
          final container = ProviderScope.containerOf(
            tester.element(find.byType(MaterialApp)),
          );
          await container.read(lookupServiceProvider.future);
        });
        reporter.logTiming('Αρχική φόρτωση UI (pump frames)', sw.elapsed);
        sw.reset();

        expect(
          find.byType(NavigationRail),
          findsOneWidget,
          reason: greekExpectMsg('Κύριο κέλυφος με πλευρική πλοήγηση (οθόνη Κλήσεων χωρίς AppBar τίτλου)'),
        );

        final phoneField = callLoggerPhoneTextField();
        expect(
          phoneField,
          findsOneWidget,
          reason: greekExpectMsg('Πεδίο τηλεφώνου (Semantics: Αριθμός τηλεφώνου)'),
        );
        reporter.logStep('Αυτόματη πληκτρολόγηση εσωτερικού τηλεφώνου');
        await tester.tap(phoneField);
        await pumpUntilSettled(tester);
        await tester.enterText(phoneField, kTestPhoneDigits);
        await tester.pump(); // trigger onChanged
        await tester.pump(const Duration(milliseconds: 500)); // debounce / async lookup
        await pumpUntilSettled(tester);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        // Μετά το Done: debounce 250 ms πριν το performPhoneLookup στο πεδίο τηλεφώνου.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
        // Blur: Future.delayed 150 ms + επιπλέον debounce 250 ms στο _scheduleCompletedLookup.
        await tester.pump(const Duration(milliseconds: 450));

        sw.start();
        await pumpUntilSettled(tester, steps: 40, step: const Duration(milliseconds: 60));
        reporter.logTiming('Lookup μετά πληκτρολόγηση τηλεφώνου', sw.elapsed);
        // Επιπλέον χρόνος για debounce lookup + async ενημέρωση UI (κάρτα χρήστη).
        await pumpUntilSettledLong(tester);
        expect(
          find.textContaining(kTestUserFirstName),
          findsWidgets,
          reason: greekExpectMsg(
            'Μετά το lookup ο καλώντας από το seed πρέπει να εμφανίζεται (ή σε πεδίο ή σε κάρτα)',
          ),
        );
        reporter.logStep('Επιβεβαίωση εμφάνισης εξοπλισμού και τμήματος μετά το lookup');
        expect(
          find.textContaining(kTestEquipmentCode),
          findsWidgets,
          reason: greekExpectMsg(
            'Ο κωδικός εξοπλισμού του seed πρέπει να εμφανίζεται (π.χ. στην κάρτα εξοπλισμού)',
          ),
        );
        expect(
          find.textContaining(kTestDepartmentName),
          findsWidgets,
          reason: greekExpectMsg('Το τμήμα του seed πρέπει να συμπληρώνεται ή να εμφανίζεται στο προφίλ'),
        );

        final categoryField = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.labelText?.contains('Κατηγορία') ?? false),
        );
        expect(
          categoryField,
          findsOneWidget,
          reason: greekExpectMsg('Πεδίο κατηγορίας προβλήματος'),
        );
        reporter.logStep('Συμπλήρωση κατηγορίας προβλήματος');
        await tester.tap(categoryField);
        await pumpUntilSettled(tester);
        await tester.enterText(categoryField, kTestCategoryName);
        await pumpUntilSettled(tester);

        final notesFinder = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText?.contains('Σημειώσεις') ?? false),
        );
        expect(notesFinder, findsOneWidget, reason: greekExpectMsg('Πεδίο σημειώσεων'));
        reporter.logStep('Συμπλήρωση σημειώσεων');
        await tester.tap(notesFinder);
        await pumpUntilSettled(tester);
        await tester.enterText(
          notesFinder,
          '$kTestHistorySearchMarker happy path',
        );
        await pumpUntilSettled(tester);

        final submitFinder = find.widgetWithText(ElevatedButton, 'Καταγραφή');
        expect(
          tester.widget<ElevatedButton>(submitFinder).onPressed,
          isNotNull,
          reason: greekExpectMsg('Με συμπληρωμένο τηλέφωνο το κουμπί υποβολής πρέπει να είναι ενεργό'),
        );

        reporter.logStep('Υποβολή καταγραφής κλήσης');
        final scopeCtx = tester.element(submitFinder);
        final container = ProviderScope.containerOf(scopeCtx);
        final submitOk = await tester.runAsync(() async {
          return container.read(callEntryProvider.notifier).submitCall();
        });
        expect(
          submitOk,
          isTrue,
          reason: greekExpectMsg(
            'Η υποβολή κλήσης πρέπει να ολοκληρωθεί επιτυχώς',
          ),
        );
        await tester.pump();

        final saved = await tester.runAsync(() async {
          final db = await DatabaseHelper.instance.database;
          return db.query(
            'calls',
            where: 'issue LIKE ? AND phone_text = ?',
            whereArgs: ['%$kTestHistorySearchMarker%', kTestPhoneDigits],
          );
        });
        await tester.pump();
        expect(
          saved,
          isNotEmpty,
          reason: greekExpectMsg(
            'Η κλήση πρέπει να αποθηκευτεί στην απομονωμένη βάση (κείμενο σημειώσεων + τηλέφωνο)',
          ),
        );
        reporter.recordPass('Καταγραφή κλήσης με απομονωμένη βάση');
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // Συμπτυγμένη όψη: η επέκταση μόνο μετά ολοκλήρωση καταχώρησης τηλεφώνου (όχι στα 2 ψηφία).
    testWidgets(
      'συμπτυγμένη: 2 ψηφία κατά την πληκτρολόγηση δεν επεκτείνουν οθόνη',
      (tester) async {
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

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        final phoneField = callLoggerPhoneTextField();

        await tester.tap(phoneField);
        await pumpUntilSettled(tester);
        await tester.enterText(phoneField, '28');
        await tester.pump();

        expect(
          container.read(callsScreenIsExpandedProvider),
          isTrue,
          reason: greekExpectMsg(
            'Με εστίαση/πληκτρολόγηση τηλεφώνου η κεφαλίδα μένει πάνω (expanded latch)',
          ),
        );
        expect(
          container.read(callsFieldGroupsProvider).anyGroupActive,
          isFalse,
          reason: greekExpectMsg(
            'Με 2 ψηφία κατά την πληκτρολόγηση καμία ομάδα πεδίων δεν είναι ενεργή',
          ),
        );
        expect(
          find.widgetWithText(ElevatedButton, 'Καταγραφή'),
          findsNothing,
          reason: greekExpectMsg(
            'Χωρίς επιβεβαίωση τηλεφώνου δεν εμφανίζεται κουμπί Καταγραφή',
          ),
        );
        expect(
          find.byType(NotesStickyField),
          findsNothing,
          reason: greekExpectMsg(
            'Με 2 ψηφία κατά την πληκτρολόγηση δεν εμφανίζονται σημειώσεις',
          ),
        );

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 300));
        await pumpUntilSettled(tester);

        expect(
          container.read(callsScreenIsExpandedProvider),
          isTrue,
          reason: greekExpectMsg(
            'Μετά submit (Done) του τηλεφώνου η οθόνη επεκτείνεται',
          ),
        );
        expect(
          find.byType(NotesStickyField),
          findsOneWidget,
          reason: greekExpectMsg(
            'Μετά submit (Done) εμφανίζονται σημειώσεις',
          ),
        );

        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    testWidgets(
      'συμπτυγμένη: submit τηλεφώνου συμπληρώνει καλούντα και εξοπλισμό μετά την επέκταση',
      (tester) async {
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

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        final phoneField = callLoggerPhoneTextField();

        await tester.tap(phoneField);
        await pumpUntilSettled(tester);
        await tester.enterText(phoneField, kTestPhoneDigits);
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 300));
        await pumpUntilSettled(tester);

        expect(
          container.read(callsScreenIsExpandedProvider),
          isTrue,
          reason: greekExpectMsg('Μετά submit τηλεφώνου η οθόνη επεκτείνεται'),
        );
        expect(
          find.textContaining(kTestUserFirstName),
          findsWidgets,
          reason: greekExpectMsg(
            'Μετά submit στη συμπτυγμένη όψη συμπληρώνεται ο καλούντας',
          ),
        );
        expect(
          find.text(kTestEquipmentCode),
          findsOneWidget,
          reason: greekExpectMsg(
            'Μετά submit στη συμπτυγμένη όψη συμπληρώνεται ο εξοπλισμός',
          ),
        );

        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // Χωρίς ενεργή Ομάδα Τηλεφώνου το κουμπί «Καταγραφή» δεν εμφανίζεται στη διάταξη.
    //   flutter test test/features/calls/call_form_test.dart --plain-name "Unhappy path: απενεργοποιημένο κουμπί χωρίς τηλέφωνο"
    testWidgets(
      'Unhappy path: απενεργοποιημένο κουμπί χωρίς τηλέφωνο',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();
        reporter.logStep('Έναρξη unhappy path: compact χωρίς Ομάδα Τηλεφώνου');

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

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        expect(
          container.read(callHeaderProvider).canSubmitCall,
          isFalse,
          reason: greekExpectMsg('Χωρίς τηλέφωνο το canSubmitCall είναι false'),
        );
        expect(
          find.widgetWithText(ElevatedButton, 'Καταγραφή'),
          findsNothing,
          reason: greekExpectMsg(
            'Σε compact όψη χωρίς Ομάδα Τηλεφώνου δεν εμφανίζεται κουμπί Καταγραφή',
          ),
        );
        reporter.recordPass('Unhappy path: compact χωρίς κουμπί υποβολής');
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    testWidgets(
      'expanded latch κενά πεδία: κεφαλίδα πάνω, χωρίς widget κάτω',
      (tester) async {
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

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        final phoneField = callLoggerPhoneTextField();

        await tester.tap(phoneField);
        await pumpUntilSettled(tester);
        await tester.enterText(phoneField, kTestPhoneDigits);
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUntilSettled(tester);

        expect(
          container.read(callsScreenIsExpandedProvider),
          isTrue,
          reason: greekExpectMsg('Μετά επιβεβαίωση τηλεφώνου → expanded'),
        );
        expect(
          find.byType(NotesStickyField),
          findsOneWidget,
          reason: greekExpectMsg('Με ενεργή ομάδα τηλεφώνου εμφανίζονται σημειώσεις'),
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
        expect(find.byType(NotesStickyField), findsNothing);
        expect(find.byType(CategoryAutocompleteField), findsNothing);
        expect(find.byType(CallStatusBar), findsNothing);
        expect(find.widgetWithText(ElevatedButton, 'Καταγραφή'), findsNothing);
        expect(
          find.widgetWithText(OutlinedButton, 'Εκκαθάριση'),
          findsOneWidget,
          reason: greekExpectMsg(
            'Expanded latch κενά πεδία: το Εκκαθάριση παραμένει στο anchor κάτω δεξιά',
          ),
        );

        await tester.runAsync(() async {
          await container
              .read(showGlobalCallsToggleProvider.notifier)
              .setVisible(true);
        });
        await pumpUntilSettled(tester);

        expect(
          find.byType(GlobalRecentCallsList),
          findsOneWidget,
          reason: greekExpectMsg(
            'Expanded latch + κενά πεδία: η κάρτα ΤΚ εμφανίζεται στο πλάνο',
          ),
        );

        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
