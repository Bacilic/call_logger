// Φρουρός εναλλαγής βάσης — εμπόδια ανοιχτής κλήσης / Lansweeper / backup.
//
//   flutter test test/core/init/database_switch_guard_test.dart

import 'package:call_logger/core/init/database_switch_guard.dart';
import 'package:call_logger/core/providers/active_critical_operations_provider.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<WidgetRef> _pumpWidgetRef(
  WidgetTester tester,
  ProviderContainer container, {
  Widget Function(BuildContext context, WidgetRef ref)? home,
}) async {
  late WidgetRef widgetRef;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            widgetRef = ref;
            if (home != null) return home(context, ref);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return widgetRef;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'καθαρή φόρμα κλήσης → collectDatabaseSwitchBlockers κενή',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      expect(collectDatabaseSwitchBlockers(ref), isEmpty);
    },
  );

  testWidgets(
    'setCaller + setCategory → εμπόδιο openCallForm (interruptible)',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      container.read(callSmartEntityProvider.notifier).setCaller(
            UserModel(id: 42, firstName: 'Δοκιμή', lastName: 'Καλούντας'),
          );
      container.read(callEntryProvider.notifier).setCategory(
            'Δίκτυο',
            categoryId: 3,
          );

      final blockers = collectDatabaseSwitchBlockers(ref);
      expect(blockers, isNotEmpty);
      expect(
        blockers.any(
          (b) =>
              b.kind == DatabaseSwitchBlockerKind.openCallForm &&
              b.interruptible,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'μόνο ενεργό χρονόμετρο → εμπόδιο openCallForm',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      container.read(callEntryProvider.notifier).startTimerOnce();

      final blockers = collectDatabaseSwitchBlockers(ref);
      expect(
        blockers.any(
          (b) => b.kind == DatabaseSwitchBlockerKind.openCallForm,
        ),
        isTrue,
      );

      container.read(callEntryProvider.notifier).reset();
    },
  );

  testWidgets(
    'μητρώο lansweeperTicketSubmit → μη διακόψιμο εμπόδιο· end το αφαιρεί',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      final ops = container.read(activeCriticalOperationsProvider.notifier);
      ops.begin(CriticalOperation.lansweeperTicketSubmit);

      final whileRunning = collectDatabaseSwitchBlockers(ref);
      expect(
        whileRunning.any(
          (b) =>
              b.kind == DatabaseSwitchBlockerKind.lansweeperSubmitRunning &&
              !b.interruptible,
        ),
        isTrue,
      );

      ops.end(CriticalOperation.lansweeperTicketSubmit);
      expect(collectDatabaseSwitchBlockers(ref), isEmpty);
    },
  );

  testWidgets(
    'ensureDatabaseSwitchAllowed · Διακοπή κλήσης → true και καθαρή φόρμα',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      bool? allowed;
      await _pumpWidgetRef(
        tester,
        container,
        home: (context, ref) => Scaffold(
          body: TextButton(
            onPressed: () async {
              allowed = await ensureDatabaseSwitchAllowed(context, ref);
            },
            child: const Text('trigger'),
          ),
        ),
      );

      container.read(callSmartEntityProvider.notifier).setCaller(
            UserModel(id: 7, firstName: 'Άννα', lastName: 'Δοκιμή'),
          );
      container.read(callEntryProvider.notifier).setCategory('Υλικό');
      container.read(callEntryProvider.notifier).startTimerOnce();

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Διακοπή κλήσης'), findsOneWidget);
      await tester.tap(find.text('Διακοπή κλήσης'));
      await tester.pumpAndSettle();

      expect(allowed, isTrue);
      expect(
        container.read(callSmartEntityProvider).selectedCaller,
        isNull,
      );
      expect(container.read(callEntryProvider).category, isEmpty);
      expect(container.read(callEntryProvider).durationSeconds, 0);
    },
  );

  testWidgets(
    'μη διακόψιμο εμπόδιο · χωρίς «Διακοπή κλήσης» · επιστρέφει false',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      bool? allowed;
      await _pumpWidgetRef(
        tester,
        container,
        home: (context, ref) => Scaffold(
          body: TextButton(
            onPressed: () async {
              allowed = await ensureDatabaseSwitchAllowed(context, ref);
            },
            child: const Text('trigger'),
          ),
        ),
      );

      container
          .read(activeCriticalOperationsProvider.notifier)
          .begin(CriticalOperation.lansweeperTicketSubmit);

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Διακοπή κλήσης'), findsNothing);
      expect(find.text('Εντάξει, θα περιμένω'), findsOneWidget);
      await tester.tap(find.text('Εντάξει, θα περιμένω'));
      await tester.pumpAndSettle();

      expect(allowed, isFalse);
    },
  );
}
