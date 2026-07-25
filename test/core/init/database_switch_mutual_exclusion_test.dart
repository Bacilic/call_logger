// Δ5β-3: αμοιβαίος αποκλεισμός εναλλαγής βάσης ↔ αντιγράφου, και εκκαθάριση
// των providers του Καταλόγου (που κρατούν γραμμές + `lastDeleted` της παλιάς βάσης).
//
//   flutter test test/core/init/database_switch_mutual_exclusion_test.dart

import 'package:call_logger/core/init/database_reopen_cache_reset.dart';
import 'package:call_logger/core/init/database_switch_guard.dart';
import 'package:call_logger/core/providers/active_critical_operations_provider.dart';
import 'package:call_logger/features/directory/providers/category_directory_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<WidgetRef> _pumpWidgetRef(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late WidgetRef widgetRef;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            widgetRef = ref;
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

  group('runGuardedDatabaseSwitch · δήλωση εναλλαγής', () {
    testWidgets(
      'δηλώνει databaseSwitch ΚΑΤΑ τη διάρκεια και το καθαρίζει μετά',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final ref = await _pumpWidgetRef(tester, container);

        expect(
          container.read(activeCriticalOperationsProvider),
          isNot(contains(CriticalOperation.databaseSwitch)),
        );

        bool? declaredDuringAction;
        final ran = await runGuardedDatabaseSwitch(
          tester.element(find.byType(SizedBox)),
          ref,
          () async {
            declaredDuringAction = container
                .read(activeCriticalOperationsProvider)
                .contains(CriticalOperation.databaseSwitch);
          },
        );

        expect(ran, isTrue);
        expect(
          declaredDuringAction,
          isTrue,
          reason: 'Ο χρονοδιακόπτης αντιγράφων πρέπει να «βλέπει» την εναλλαγή',
        );
        expect(
          container.read(activeCriticalOperationsProvider),
          isNot(contains(CriticalOperation.databaseSwitch)),
          reason: 'Η δήλωση οφείλει να καθαρίζει μετά την ολοκλήρωση',
        );
      },
    );

    testWidgets(
      'η δήλωση καθαρίζει ΚΑΙ όταν η ροή εναλλαγής πετάξει εξαίρεση',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final ref = await _pumpWidgetRef(tester, container);

        await expectLater(
          runGuardedDatabaseSwitch(
            tester.element(find.byType(SizedBox)),
            ref,
            () async => throw StateError('αποτυχία εναλλαγής'),
          ),
          throwsStateError,
        );

        expect(
          container.read(activeCriticalOperationsProvider),
          isNot(contains(CriticalOperation.databaseSwitch)),
          reason: 'Χωρίς finally το αντίγραφο θα έμενε μπλοκαρισμένο για πάντα',
        );
      },
    );

    testWidgets(
      'μη διακόψιμο εμπόδιο → η action ΔΕΝ τρέχει και δεν δηλώνεται εναλλαγή',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final ref = await _pumpWidgetRef(tester, container);

        container
            .read(activeCriticalOperationsProvider.notifier)
            .begin(CriticalOperation.lansweeperTicketSubmit);

        var actionRan = false;
        final future = runGuardedDatabaseSwitch(
          tester.element(find.byType(SizedBox)),
          ref,
          () async => actionRan = true,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Εντάξει, θα περιμένω'));
        await tester.pumpAndSettle();

        expect(await future, isFalse);
        expect(actionRan, isFalse);
        expect(
          container.read(activeCriticalOperationsProvider),
          isNot(contains(CriticalOperation.databaseSwitch)),
        );
      },
    );
  });

  testWidgets(
    'invalidateDatabaseScopedCaches ακυρώνει τους providers του Καταλόγου',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = await _pumpWidgetRef(tester, container);

      // Σημάδι «παλιάς βάσης» στην κατάσταση κάθε καρτέλας.
      container.read(directoryProvider.notifier).setSearchQuery('ΠΑΛΙΑ_ΒΑΣΗ');
      container
          .read(departmentDirectoryProvider.notifier)
          .setSearchQuery('ΠΑΛΙΑ_ΒΑΣΗ');
      container
          .read(equipmentDirectoryProvider.notifier)
          .setSearchQuery('ΠΑΛΙΑ_ΒΑΣΗ');
      container
          .read(categoryDirectoryProvider.notifier)
          .setSearchQuery('ΠΑΛΙΑ_ΒΑΣΗ');

      expect(container.read(directoryProvider).searchQuery, 'ΠΑΛΙΑ_ΒΑΣΗ');

      invalidateDatabaseScopedCaches(ref);
      await tester.pump();

      expect(
        container.read(directoryProvider).searchQuery,
        isEmpty,
        reason: 'Ο Κατάλογος υπαλλήλων κρατούσε κατάσταση της παλιάς βάσης',
      );
      expect(container.read(departmentDirectoryProvider).searchQuery, isEmpty);
      expect(container.read(equipmentDirectoryProvider).searchQuery, isEmpty);
      expect(
        container.read(categoryDirectoryProvider).searchQuery,
        isEmpty,
        reason: 'Το `lastDeleted` της αναίρεσης δείχνει σε ids της παλιάς βάσης',
      );
    },
  );
}
