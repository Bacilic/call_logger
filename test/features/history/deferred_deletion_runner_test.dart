// Unit tests: δρομέας αναβαλλόμενης διαγραφής με παράθυρο αναίρεσης.
//
//   flutter test test/features/history/deferred_deletion_runner_test.dart

import 'package:call_logger/core/providers/pending_deferred_actions_provider.dart';
import 'package:call_logger/features/history/services/deferred_deletion_runner.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeferredDeletionRunner', () {
    test('λήξη παραθύρου → εκτελείται μία φορά και το μητρώο αδειάζει', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(
          pendingDeferredActionsProvider.notifier,
        );
        var executed = 0;
        final finishedWith = <bool>[];

        DeferredDeletionRunner.schedule(
          deferredActions: notifier,
          label: 'δοκιμή',
          execute: () async => executed++,
          onFinished: finishedWith.add,
        );
        expect(container.read(pendingDeferredActionsProvider), hasLength(1));
        expect(executed, 0);
        expect(finishedWith, isEmpty);

        async.elapse(const Duration(seconds: 6));
        expect(executed, 1);
        expect(finishedWith, [true]);
        expect(container.read(pendingDeferredActionsProvider), isEmpty);
      });
    });

    test('αναίρεση εντός παραθύρου → καμία εκτέλεση, μητρώο άδειο', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(
          pendingDeferredActionsProvider.notifier,
        );
        var executed = 0;

        final runner = DeferredDeletionRunner.schedule(
          deferredActions: notifier,
          label: 'δοκιμή',
          execute: () async => executed++,
        );
        runner.undo();

        expect(container.read(pendingDeferredActionsProvider), isEmpty);
        async.elapse(const Duration(seconds: 6));
        expect(executed, 0);
      });
    });

    test('εναλλαγή βάσης πριν τη λήξη → εκτελείται τώρα και όχι ξανά μετά', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(
          pendingDeferredActionsProvider.notifier,
        );
        var executed = 0;
        final finishedWith = <bool>[];

        DeferredDeletionRunner.schedule(
          deferredActions: notifier,
          label: 'δοκιμή',
          execute: () async => executed++,
          onFinished: finishedWith.add,
        );

        List<String>? settledLabels;
        notifier.settleAll().then((labels) => settledLabels = labels);
        async.flushMicrotasks();

        expect(executed, 1);
        expect(settledLabels, ['δοκιμή']);
        expect(finishedWith, [true]);

        async.elapse(const Duration(seconds: 6));
        expect(executed, 1);
        expect(finishedWith, [true]);
      });
    });

    test('αναίρεση μετά τη λήξη → δεν αλλάζει τίποτα', () {
      fakeAsync((async) {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(
          pendingDeferredActionsProvider.notifier,
        );
        var executed = 0;

        final runner = DeferredDeletionRunner.schedule(
          deferredActions: notifier,
          label: 'δοκιμή',
          execute: () async => executed++,
        );
        async.elapse(const Duration(seconds: 6));
        expect(executed, 1);

        runner.undo();
        expect(executed, 1);
        expect(container.read(pendingDeferredActionsProvider), isEmpty);
      });
    });
  });
}
