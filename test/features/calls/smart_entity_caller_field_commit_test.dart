// Widget tests: άμεσο entity lookup στο commit πεδίου Καλούντα (v2 §Ζ.5).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/calls/smart_entity_caller_field_commit_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_caller_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_department_field.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
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
    testWidgets(
      'focus-out με μερικό όνομα → callerCandidates με ένα pump',
      (tester) async {
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
        expect(header.selectedCaller, isNull, reason: greekExpectMsg('Μερικό όνομα — χωρίς επιλογή'));

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

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
        expect(header.selectedCaller, isNotNull, reason: greekExpectMsg('Πλήρες όνομα — επιλογή καλούντα'));
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
        expect(header.equipmentText, '', reason: greekExpectMsg('Ο εξοπλισμός καθαρίστηκε'));
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
        expect(header.selectedCaller, isNull, reason: greekExpectMsg('Μερικό όνομα — υποψήφιος'));

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );
  });
}
