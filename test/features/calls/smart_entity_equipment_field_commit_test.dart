// Widget tests: άμεσο entity lookup στο commit πεδίου Εξοπλισμού (v2 §Ζ.5).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/calls/smart_entity_equipment_field_commit_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_department_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_equipment_field.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kUnknownEquipmentCode = 'ZZZ-NOMATCH';

Finder _departmentTextField() {
  return find.descendant(
    of: find.byType(SmartEntityDepartmentField),
    matching: find.byType(TextField),
  );
}

Finder _equipmentTextField() {
  return find.descendant(
    of: find.byType(SmartEntityEquipmentField).first,
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

Future<void> _seedPhoneForEquipmentSuggestions(WidgetTester tester) async {
  await tester.runAsync(() async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final notifier = container.read(callHeaderProvider.notifier);
    notifier.updatePhone(kTestPhoneDigits);
    notifier.performPhoneLookup(kTestPhoneDigits);
  });
  await tester.pump();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Εξοπλισμός — άμεσο lookup στο commit (widget)', () {
    setUp(() async {
      await seedIsolatedTestDatabase();
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    // Τεστ Α: focus-out χωρίς debounce 250ms — αποτέλεσμα lookup με ένα pump.
    testWidgets(
      'focus-out με υπαρκτό κωδικό → selectedEquipment με ένα pump',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await tester.tap(_equipmentTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_equipmentTextField(), kTestEquipmentCode);
        await tester.pump();

        await tester.tap(_departmentTextField());
        await tester.pump();

        final header = await _readHeader(tester);
        expect(
          header.selectedEquipment?.code,
          kTestEquipmentCode,
          reason: greekExpectMsg('Άμεσο lookup — επιλεγμένος εξοπλισμός'),
        );
        expect(
          header.equipmentText,
          kTestEquipmentCode,
          reason: greekExpectMsg('Άμεσο lookup — κείμενο πεδίου'),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'focus-out με άγνωστο κωδικό → equipmentNoMatch με ένα pump',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await tester.tap(_equipmentTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_equipmentTextField(), _kUnknownEquipmentCode);
        await tester.pump();

        await tester.tap(_departmentTextField());
        await tester.pump();

        final header = await _readHeader(tester);
        expect(header.equipmentNoMatch, isTrue, reason: greekExpectMsg('Άμεσο lookup — no-match'));
        expect(header.selectedEquipment, isNull, reason: greekExpectMsg('Χωρίς επιλογή'));

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    // Τεστ Β: δικλείδα _performLookup — blur χωρίς αλλαγή κειμένου δεν ξαναγεμίζει καλούντα.
    testWidgets(
      'blur εξοπλισμού μετά καθαρισμό καλούντα → καλών παραμένει κενός',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await tester.tap(_equipmentTextField());
        await pumpUntilSettled(tester);
        await tester.enterText(_equipmentTextField(), kTestEquipmentCode);
        await tester.pump();
        await tester.tap(_departmentTextField());
        await tester.pump(const Duration(milliseconds: 260));

        var header = await _readHeader(tester);
        expect(header.selectedEquipment, isNotNull, reason: greekExpectMsg('Προϋπόθεση: επιλεγμένος εξοπλισμός'));
        expect(header.selectedCaller, isNotNull, reason: greekExpectMsg('Προϋπόθεση: autofill καλούντα'));

        await tester.runAsync(() async {
          final container = ProviderScope.containerOf(
            tester.element(find.byType(MaterialApp)),
          );
          container.read(callHeaderProvider.notifier).clearCaller();
        });
        await tester.pump();

        header = await _readHeader(tester);
        expect(header.selectedCaller, isNull, reason: greekExpectMsg('Ο καλών καθαρίστηκε'));
        expect(header.equipmentText, kTestEquipmentCode, reason: greekExpectMsg('Ο εξοπλισμός μένει'));

        await tester.tap(_equipmentTextField(), warnIfMissed: false);
        await pumpUntilSettled(tester);
        await tester.tap(_departmentTextField());
        await tester.pump();

        header = await _readHeader(tester);
        expect(header.selectedCaller, isNull, reason: greekExpectMsg('Blur δεν ξαναγεμίζει καλούντα'));
        expect(header.equipmentText, kTestEquipmentCode, reason: greekExpectMsg('Ο εξοπλισμός μένει'));

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    // Τεστ Γ: επιλογή από αρχική λίστα προτάσεων — σωστό selectedEquipment.
    testWidgets(
      'tap σε πρόταση αρχικής λίστας → σωστή επιλογή εξοπλισμού',
      (tester) async {
        _configureDesktopViewport(tester);
        await _pumpCallLoggerApp(tester);

        await _seedPhoneForEquipmentSuggestions(tester);

        await tester.tap(_equipmentTextField());
        await pumpUntilSettled(tester);
        await tester.pump();

        final suggestionTile = find.text(kTestEquipmentCode);
        expect(suggestionTile, findsWidgets, reason: greekExpectMsg('Εμφανής πρόταση εξοπλισμού'));
        await tester.tap(suggestionTile.first);
        await pumpUntilSettled(tester);

        final header = await _readHeader(tester);
        expect(
          header.selectedEquipment?.code,
          kTestEquipmentCode,
          reason: greekExpectMsg('Επιλογή από λίστα — id εξοπλισμού'),
        );
        expect(
          header.equipmentText,
          kTestEquipmentCode,
          reason: greekExpectMsg('Επιλογή από λίστα — κείμενο πεδίου'),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );
  });
}
