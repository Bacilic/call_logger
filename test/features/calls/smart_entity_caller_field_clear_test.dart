// Widget tests: καθαρισμός πεδίου Καλούντα δεν αδειάζει Τμήμα/Εξοπλισμό (v2 §Γ.1).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/calls/smart_entity_caller_field_clear_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_caller_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_department_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_equipment_field.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kDepartmentText = 'Δοκιμαστικό';
const _kEquipmentText = '1001';
const _kCallerText = 'Ελένη Κλήση';

Finder _departmentTextField() {
  return find.descendant(
    of: find.byType(SmartEntityDepartmentField),
    matching: find.byType(TextField),
  );
}

Finder _callerTextField() {
  return find.descendant(
    of: find.byType(SmartEntityCallerField),
    matching: find.byType(TextField),
  );
}

Finder _equipmentTextField() {
  return find.descendant(
    of: find.byType(SmartEntityEquipmentField),
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

Future<void> _fillDepartmentAndEquipment(WidgetTester tester) async {
  await tester.tap(_departmentTextField());
  await pumpUntilSettled(tester);
  await tester.enterText(_departmentTextField(), _kDepartmentText);
  await tester.pump();

  await tester.tap(_equipmentTextField());
  await pumpUntilSettled(tester);
  await tester.enterText(_equipmentTextField(), _kEquipmentText);
  await tester.pump();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Καθαρισμός Καλούντα — διατήρηση Τμήματος και Εξοπλισμού (widget)', () {
    setUp(() async {
      await seedIsolatedTestDatabase();
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    // Τεστ Γ: κουμπί «Καθαρισμός Καλούντα» δεν αδειάζει τμήμα/εξοπλισμό.
    //   flutter test test/features/calls/smart_entity_caller_field_clear_test.dart --plain-name "κουμπί καθαρισμού"
    testWidgets(
      'κουμπί καθαρισμού Καλούντα διατηρεί Τμήμα και Εξοπλισμό',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await _fillDepartmentAndEquipment(tester);

        await tester.tap(_callerTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_callerTextField(), _kCallerText);
        await tester.pump();

        final clearButton = find.byTooltip('Καθαρισμός Καλούντα');
        expect(clearButton, findsOneWidget, reason: greekExpectMsg('Εμφανές κουμπί καθαρισμού καλούντα'));
        await tester.tap(clearButton);
        await pumpUntilSettled(tester);

        final header = await _readHeader(tester);
        expect(header.departmentText, _kDepartmentText, reason: greekExpectMsg('Το τμήμα παραμένει'));
        expect(header.equipmentText, _kEquipmentText, reason: greekExpectMsg('Ο εξοπλισμός παραμένει'));
        expect(header.callerDisplayText, '', reason: greekExpectMsg('Ο καλώντας καθαρίστηκε'));

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    // Τεστ Δ: χειροκίνητο σβήσιμο κειμένου Καλούντα διατηρεί τμήμα/εξοπλισμό.
    //   flutter test test/features/calls/smart_entity_caller_field_clear_test.dart --plain-name "χειροκίνητο σβήσιμο"
    testWidgets(
      'χειροκίνητο σβήσιμο Καλούντα διατηρεί Τμήμα και Εξοπλισμό',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await _fillDepartmentAndEquipment(tester);

        await tester.tap(_callerTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_callerTextField(), _kCallerText);
        await tester.pump();

        await tester.enterText(_callerTextField(), '');
        await tester.pump();

        final header = await _readHeader(tester);
        expect(header.departmentText, _kDepartmentText, reason: greekExpectMsg('Το τμήμα παραμένει'));
        expect(header.equipmentText, _kEquipmentText, reason: greekExpectMsg('Ο εξοπλισμός παραμένει'));
        expect(header.callerDisplayText, '', reason: greekExpectMsg('Ο καλώντας καθαρίστηκε'));

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );
  });
}
