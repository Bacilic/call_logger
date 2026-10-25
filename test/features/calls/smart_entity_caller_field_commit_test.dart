// Widget tests: άμεσο entity lookup στο commit πεδίου Καλούντα.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/calls/smart_entity_caller_field_commit_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_caller_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_department_field.dart';
import 'package:call_logger/features/calls/utils/caller_field_options.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kFullCallerName = '$kTestUserFirstName $kTestUserLastName';

Finder _departmentTextField() {
  return find.descendant(
    of: find.byType(SmartEntityDepartmentField),
    matching: find.byType(TextField),
  );
}

Finder _callerTextField() {
  return find.descendant(
    of: find.byType(SmartEntityCallerField).first,
    matching: find.byType(TextField),
  );
}

Future<void> _pumpCallLoggerApp(WidgetTester tester) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: callLoggerTestProviderOverrides(),
        child: const MyApp(showStartupScreens: false),
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
  await tester.pump();
}

Future<CallHeaderState> _readHeader(WidgetTester tester) async {
  CallHeaderState? state;
  await tester.runAsync(() async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    state = container.read(callHeaderProvider);
  });
  await tester.pump();
  return state!;
}

void _configureDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Καλούντας — άμεσο lookup στο commit (widget)', () {
    setUp(() async {
      await seedIsolatedTestDatabase();
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    // Τεστ Α: focus-out χωρίς debounce 250ms — αποτέλεσμα lookup με ένα pump.
    testWidgets('focus-out με μερικό όνομα → callerCandidates με ένα pump', (
      tester,
    ) async {
      _configureDesktopViewport(tester);
      await _pumpCallLoggerApp(tester);

      await tester.tap(_callerTextField());
      await pumpUntilSettled(tester);
      await tester.enterText(_callerTextField(), kTestUserFirstName);
      await tester.pump();

      await tester.tap(_departmentTextField());
      await tester.pump();

      final header = await _readHeader(tester);
      expect(
        header.callerCandidates.length,
        1,
        reason: greekExpectMsg('Άμεσο lookup — ένας υποψήφιος καλώντας'),
      );
      expect(
        header.selectedCaller,
        isNull,
        reason: greekExpectMsg('Μερικό όνομα — χωρίς επιλογή'),
      );

      await flushCallLoggerSqfliteLockTimers(tester);
    }, semanticsEnabled: false);

    // Τεστ Β: Enter με ήδη επιλεγμένο καλούντα δεν ξανατρέχει lookup / autofill εξοπλισμού.
    testWidgets(
      'Enter με selectedCaller → εξοπλισμός μένει κενός μετά καθαρισμό',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await tester.tap(_callerTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_callerTextField(), _kFullCallerName);
        await tester.pump();
        await tester.tap(_departmentTextField());
        await tester.pump();

        var header = await _readHeader(tester);
        expect(
          header.selectedCaller,
          isNotNull,
          reason: greekExpectMsg('Πλήρες όνομα — επιλογή καλούντα'),
        );
        expect(
          header.equipmentText,
          kTestEquipmentCode,
          reason: greekExpectMsg('Autofill εξοπλισμού από πρώτο lookup'),
        );

        await tester.runAsync(() async {
          final container = ProviderScope.containerOf(
            tester.element(find.byType(MaterialApp)),
          );
          container.read(callHeaderProvider.notifier).clearEquipment();
        });
        await tester.pump();

        header = await _readHeader(tester);
        expect(
          header.equipmentText,
          '',
          reason: greekExpectMsg('Ο εξοπλισμός καθαρίστηκε'),
        );
        expect(header.selectedEquipment, isNull);

        await tester.tap(_callerTextField(), warnIfMissed: false);
        await pumpUntilSettled(tester);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 260));

        header = await _readHeader(tester);
        expect(
          header.equipmentText,
          '',
          reason: greekExpectMsg('Enter δεν ξαναγεμίζει τον εξοπλισμό'),
        );
        expect(header.selectedEquipment, isNull);

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    // Τεστ Γ: Enter χωρίς selectedCaller → άμεσο lookup.
    testWidgets(
      'Enter με ελεύθερο κείμενο → άμεσο callerCandidates χωρίς debounce',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await tester.tap(_callerTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_callerTextField(), kTestUserFirstName);
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        final header = await _readHeader(tester);
        expect(
          header.callerCandidates.length,
          1,
          reason: greekExpectMsg('Άμεσο lookup με Enter'),
        );
        expect(
          header.selectedCaller,
          isNull,
          reason: greekExpectMsg('Μερικό όνομα — υποψήφιος'),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    // Η λίστα που φαίνεται και η λίστα που διαβάζουν τα βελάκια ήταν κάποτε
    // δύο αντίγραφα· αν απέκλιναν, το Enter θα διάλεγε άλλον υπάλληλο από
    // αυτόν που φαινόταν επισημασμένος.
    testWidgets(
      'βελάκι και Enter → επιλέγεται ακριβώς η γραμμή που φαίνεται επισημασμένη',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await tester.tap(_callerTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_callerTextField(), kTestUserFirstName);
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        final highlighted = find.byWidgetPredicate(
          (w) => w is ListTile && w.selected,
        );
        expect(
          highlighted,
          findsOneWidget,
          reason: greekExpectMsg('Το βελάκι επισημαίνει μία πρόταση'),
        );
        final highlightedLabel =
            (tester.widget<ListTile>(highlighted).title! as Text).data;

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        final header = await _readHeader(tester);
        expect(
          header.selectedCaller?.fullNameWithDepartment,
          highlightedLabel,
          reason: greekExpectMsg(
            'Το Enter διαλέγει τον υπάλληλο της επισημασμένης γραμμής',
          ),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    // Φωτογραφία της σημερινής συμπεριφοράς των πλήκτρων, πριν μαζευτεί ο
    // χειρισμός τους σε ένα σημείο: τι γράφει το πεδίο σε κάθε βελάκι και τι
    // επιλέγει το Enter, στη μικρή λίστα και στις προτάσεις.
    group('πλήκτρα', () {
      Future<void> openSmallListWithCandidate(WidgetTester tester) async {
        await tester.tap(_callerTextField());
        await pumpUntilSettled(tester);
        // Υποψήφιοι χωρίς να γραφτεί τίποτα στο πεδίο: έτσι φαίνεται η
        // μικρή λίστα «υποψήφιοι + Άγνωστος».
        await tester.runAsync(() async {
          ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
              .read(callHeaderProvider.notifier)
              .performCallerLookup(kTestUserFirstName);
        });
        await tester.pump();
        await tester.pump();
      }

      String fieldText(WidgetTester tester) =>
          tester.widget<TextField>(_callerTextField()).controller!.text;

      testWidgets(
        'μικρή λίστα: ↓ γράφει μόνο το όνομα, και ο δεύτερος ↓ φτάνει στο «Άγνωστος»',
        (tester) async {
          _configureDesktopViewport(tester);
          await _pumpCallLoggerApp(tester);
          await openSmallListWithCandidate(tester);
          expect((await _readHeader(tester)).callerCandidates, hasLength(1));
          expect(find.text(kCallerUnknownOption), findsOneWidget);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          expect(fieldText(tester), _kFullCallerName);

          // Η προεπισκόπηση γέμισε το πεδίο, αλλά ο χρήστης δεν έγραψε
          // τίποτα: το «Άγνωστος» μένει στη λίστα και φτάνεται.
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          expect(fieldText(tester), kCallerUnknownOption);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump();
          expect(fieldText(tester), _kFullCallerName);

          await flushCallLoggerSqfliteLockTimers(tester);
        },
        semanticsEnabled: false,
      );

      testWidgets('μικρή λίστα: ↓ ↓ Enter → επιλέγεται το «Άγνωστος»', (
        tester,
      ) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);
        await openSmallListWithCandidate(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        final header = await _readHeader(tester);
        expect(header.selectedCaller, isNull);
        expect(header.callerDisplayText, kCallerUnknownOption);
        expect(fieldText(tester), kCallerUnknownOption);

        await flushCallLoggerSqfliteLockTimers(tester);
      }, semanticsEnabled: false);

      testWidgets('μικρή λίστα: Enter στον υποψήφιο → επιλέγεται', (
        tester,
      ) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);
        await openSmallListWithCandidate(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        final header = await _readHeader(tester);
        expect(header.selectedCaller?.name, _kFullCallerName);
        expect(fieldText(tester), _kFullCallerName);

        await flushCallLoggerSqfliteLockTimers(tester);
      }, semanticsEnabled: false);

      testWidgets(
        'προτάσεις: ↓ γράφει όνομα και τμήμα, το Enter αφήνει μόνο το όνομα',
        (tester) async {
          _configureDesktopViewport(tester);
          await _pumpCallLoggerApp(tester);

          await tester.tap(_callerTextField());
          await pumpUntilSettled(tester);
          await tester.enterText(_callerTextField(), kTestUserFirstName);
          await tester.pump();

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
          expect(fieldText(tester), '$_kFullCallerName ($kTestDepartmentName)');

          // Ένα στοιχείο: ↑ μένει εκεί.
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump();
          expect(fieldText(tester), '$_kFullCallerName ($kTestDepartmentName)');

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(fieldText(tester), _kFullCallerName);
          expect(
            (await _readHeader(tester)).selectedCaller?.name,
            _kFullCallerName,
          );

          await flushCallLoggerSqfliteLockTimers(tester);
        },
        semanticsEnabled: false,
      );
    });

    // Ένα μόνο σβησμένο γράμμα και έξοδος: παλιότερα το λύσιμο άδειαζε το
    // κείμενο της φόρμας, και στην έξοδο το πεδίο άδειαζε κι αυτό.
    testWidgets(
      'αλλαγμένο κείμενο σε δεμένο καλούντα → λύνεται και το κείμενο μένει',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await tester.tap(_callerTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_callerTextField(), _kFullCallerName);
        await tester.pump();
        await tester.tap(_departmentTextField());
        await tester.pump();
        var header = await _readHeader(tester);
        expect(header.selectedCaller, isNotNull);

        final edited = _kFullCallerName.substring(
          0,
          _kFullCallerName.length - 1,
        );
        await tester.tap(_callerTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_callerTextField(), edited);
        await tester.pump();

        await tester.tap(_departmentTextField());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(
          tester.widget<TextField>(_callerTextField()).controller!.text,
          edited,
          reason: greekExpectMsg('Το πεδίο δεν αδειάζει στην έξοδο'),
        );
        header = await _readHeader(tester);
        expect(
          header.selectedCaller,
          isNull,
          reason: greekExpectMsg('Το κείμενο δεν ταιριάζει πια — λύνεται'),
        );
        expect(
          header.callerDisplayText,
          edited,
          reason: greekExpectMsg(
            'Η φόρμα κρατά ό,τι γράφει το πεδίο — αυτό θα καταγραφεί',
          ),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );
  });
}
