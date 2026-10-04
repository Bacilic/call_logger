import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_state.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/settings/widgets/start_from_beginning_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

const _kResetButton = 'Ξεκίνα από την αρχή (Επαναφορά ρυθμίσεων)';
const _kResetHeading = 'Επαναφορά εφαρμογής';

Operator _operator({
  bool isAdmin = false,
  Map<String, bool> overrides = const <String, bool>{},
}) => Operator(
  id: 7,
  displayName: 'Χρήστης 7',
  isAdmin: isAdmin,
  permissionOverrides: overrides,
  createdAt: DateTime(2026, 10, 2),
);

Future<void> _pumpSection(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ApplicationResetSection())),
    ),
  );
}

void main() {
  group('hasOpenCallSession', () {
    final emptyEntry = CallEntryState();
    final emptyHeader = SmartEntitySelectorState();

    test('εντελώς κενή φόρμα → false', () {
      expect(hasOpenCallSession(emptyEntry, emptyHeader), isFalse);
    });

    test('μόνο callerDisplayText συμπληρωμένο → true', () {
      final header = SmartEntitySelectorState(callerDisplayText: 'Γιάννης');
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο equipmentText συμπληρωμένο → true', () {
      final header = SmartEntitySelectorState(equipmentText: 'PC-01');
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο selectedCaller → true', () {
      final header = SmartEntitySelectorState(
        selectedCaller: UserModel(id: 1, firstName: 'Test'),
      );
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο selectedPhone → true', () {
      final header = SmartEntitySelectorState(selectedPhone: '2262');
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο departmentText → true', () {
      final header = SmartEntitySelectorState(departmentText: 'IT');
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο selectedEquipment → true', () {
      final header = SmartEntitySelectorState(
        selectedEquipment: EquipmentModel(id: 5, code: 'EQ-1'),
      );
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('entry.notes → true', () {
      final entry = CallEntryState(notes: 'πρόβλημα δικτύου');
      expect(hasOpenCallSession(entry, emptyHeader), isTrue);
    });

    test('entry.isCallTimerRunning → true', () {
      final entry = CallEntryState(isCallTimerRunning: true);
      expect(hasOpenCallSession(entry, emptyHeader), isTrue);
    });
  });

  group('Ποιος βλέπει την «Επαναφορά εφαρμογής»', () {
    setUp(CurrentOperator.reset);
    tearDown(CurrentOperator.reset);

    testWidgets('ο απλός χρήστης δεν βλέπει ούτε την επικεφαλίδα', (
      tester,
    ) async {
      CurrentOperator.activate(_operator());
      await _pumpSection(tester);

      expect(
        find.text(_kResetButton),
        findsNothing,
        reason: greekExpectMsg('Κλειστό από προεπιλογή — κρύβεται, όχι γκρίζο'),
      );
      expect(find.text(_kResetHeading), findsNothing);
    });

    testWidgets('χρήστης με ρητό τικ το βλέπει', (tester) async {
      CurrentOperator.activate(
        _operator(overrides: {AppPermission.resetApplication.key: true}),
      );
      await _pumpSection(tester);

      expect(find.text(_kResetButton), findsOneWidget);
    });

    testWidgets('ο διαχειριστής το βλέπει', (tester) async {
      CurrentOperator.activate(_operator(isAdmin: true));
      await _pumpSection(tester);

      expect(find.text(_kResetButton), findsOneWidget);
    });

    testWidgets('χωρίς συνδεδεμένο χρήστη φαίνεται', (tester) async {
      await _pumpSection(tester);

      expect(
        find.text(_kResetButton),
        findsOneWidget,
        reason: greekExpectMsg(
          'Ζώνη ασφαλείας από λάθη, όχι κλειδαριά: χωρίς ταυτότητα τίποτα '
          'δεν κρύβεται',
        ),
      );
    });
  });
}
