// Φρουρός εναλλαγής βάσης — κατηγορία Γ (αναβαλλόμενες ενέργειες).
//
//   flutter test test/core/init/database_switch_guard_deferred_test.dart

import 'package:call_logger/core/init/database_switch_guard.dart';
import 'package:call_logger/core/providers/active_critical_operations_provider.dart';
import 'package:call_logger/core/providers/pending_deferred_actions_provider.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpScaffold(
  WidgetTester tester,
  ProviderContainer container, {
  required Future<void> Function(BuildContext context, WidgetRef ref) onTrigger,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => onTrigger(context, ref),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'register δίνει μοναδικά tokens· unregister αφαιρεί μόνο το δικό της',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(pendingDeferredActionsProvider.notifier);

      final t1 = n.register(label: 'α', settle: () async {});
      final t2 = n.register(label: 'β', settle: () async {});
      final t3 = n.register(label: 'γ', settle: () async {});

      expect(t1, isNot(equals(t2)));
      expect(t2, isNot(equals(t3)));
      expect(container.read(pendingDeferredActionsProvider).length, 3);

      n.unregister(t2);
      final remaining = container.read(pendingDeferredActionsProvider);
      expect(remaining.map((a) => a.token), [t1, t3]);
      expect(remaining.map((a) => a.label), ['α', 'γ']);
    },
  );

  test(
    'settleAll εκτελεί όλα, αδειάζει τη λίστα και επιστρέφει labels',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(pendingDeferredActionsProvider.notifier);
      final ran = <String>[];

      n.register(label: 'πρώτη', settle: () async => ran.add('πρώτη'));
      n.register(label: 'δεύτερη', settle: () async => ran.add('δεύτερη'));

      final labels = await n.settleAll();
      expect(labels, ['πρώτη', 'δεύτερη']);
      expect(ran, ['πρώτη', 'δεύτερη']);
      expect(container.read(pendingDeferredActionsProvider), isEmpty);
    },
  );

  test('settle που πετάει δεν σταματά τα υπόλοιπα· η λίστα αδειάζει', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(pendingDeferredActionsProvider.notifier);
    var secondRan = false;

    n.register(label: 'σπασμένη', settle: () async => throw StateError('boom'));
    n.register(label: 'υγιής', settle: () async => secondRan = true);

    final labels = await n.settleAll();
    expect(secondRan, isTrue);
    expect(container.read(pendingDeferredActionsProvider), isEmpty);
    expect(labels, ['υγιής']);
  });

  testWidgets('χωρίς εμπόδια · ensureDatabaseSwitchAllowed τρέχει settleAll', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var settled = false;
    bool? allowed;

    container
        .read(pendingDeferredActionsProvider.notifier)
        .register(label: 'δοκιμαστική', settle: () async => settled = true);

    await _pumpScaffold(
      tester,
      container,
      onTrigger: (context, ref) async {
        allowed = await ensureDatabaseSwitchAllowed(context, ref);
      },
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(allowed, isTrue);
    expect(settled, isTrue);
    expect(container.read(pendingDeferredActionsProvider), isEmpty);
  });

  testWidgets(
    'μη διακόψιμο εμπόδιο · settleAll ΔΕΝ τρέχει και το μητρώο μένει',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var settled = false;
      bool? allowed;

      container
          .read(pendingDeferredActionsProvider.notifier)
          .register(label: 'δοκιμαστική', settle: () async => settled = true);
      container
          .read(activeCriticalOperationsProvider.notifier)
          .begin(CriticalOperation.lansweeperTicketSubmit);

      await _pumpScaffold(
        tester,
        container,
        onTrigger: (context, ref) async {
          allowed = await ensureDatabaseSwitchAllowed(context, ref);
        },
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Εντάξει, θα περιμένω'));
      await tester.pumpAndSettle();

      expect(allowed, isFalse);
      expect(settled, isFalse);
      expect(container.read(pendingDeferredActionsProvider), isNotEmpty);
    },
  );

  testWidgets('Άκυρο αφήνει settle άθικτο· Διακοπή κλήσης το εκτελεί', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var settled = false;
    bool? allowed;

    container
        .read(pendingDeferredActionsProvider.notifier)
        .register(label: 'δοκιμαστική', settle: () async => settled = true);
    container
        .read(callSmartEntityProvider.notifier)
        .setCaller(UserModel(id: 1, firstName: 'Α', lastName: 'Β'));
    container.read(callEntryProvider.notifier).setCategory('Δίκτυο');

    await _pumpScaffold(
      tester,
      container,
      onTrigger: (context, ref) async {
        allowed = await ensureDatabaseSwitchAllowed(context, ref);
      },
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Άκυρο'));
    await tester.pumpAndSettle();

    expect(allowed, isFalse);
    expect(settled, isFalse);
    expect(container.read(pendingDeferredActionsProvider), isNotEmpty);

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Διακοπή κλήσης'));
    await tester.pumpAndSettle();

    expect(allowed, isTrue);
    expect(settled, isTrue);
    expect(container.read(pendingDeferredActionsProvider), isEmpty);
  });
}
