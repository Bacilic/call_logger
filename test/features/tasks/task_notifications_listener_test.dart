// Πότε εμφανίζεται η ειδοποίηση και πότε περιμένει.
//
// Τρεις λόγοι σιωπής, και κανένας δεν χάνει ειδοποίηση: ενεργή κλήση, κλειστή
// ρύθμιση, διάλογος ήδη ανοιχτός. Η κρατημένη ειδοποίηση εμφανίζεται μόλις ο
// λόγος πάψει να ισχύει — χωρίς να χρειάζεται νέα εγγραφή στη βάση για αφορμή.
//
//   flutter test test/features/tasks/task_notifications_listener_test.dart

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/operators/providers/operator_directory_providers.dart';
import 'package:call_logger/features/tasks/models/task_notification.dart';
import 'package:call_logger/features/tasks/providers/task_notifications_provider.dart';
import 'package:call_logger/features/tasks/widgets/task_notifications_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kDialogTitle = 'Νέα εκκρεμότητα για εσάς';

/// Ο διακόπτης «τρέχει κλήση τώρα;» μέσα στο τεστ — ώστε η μετάβαση από
/// «μιλάω» σε «τελείωσα» να γίνεται όπως στην πράξη, χωρίς πραγματικό
/// χρονόμετρο κλήσης.
class _OnCallNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final _onCall = NotifierProvider<_OnCallNotifier, bool>(_OnCallNotifier.new);

TaskNotification _notification() => TaskNotification(
  id: 1,
  taskId: 1,
  kind: TaskNotificationKind.assigned,
  taskTitle: 'Δεν τυπώνει ο εκτυπωτής του ΤΕΠ',
  createdAt: DateTime(2026, 9, 14, 9, 12),
  actorOperatorId: 22,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required List<TaskNotification> pending,
    bool enabled = true,
    bool onCall = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        operatorNamesProvider.overrideWith(
          (ref) async => {11: 'Βασίλης', 22: 'Βλάσης'},
        ),
        taskNotificationsProvider.overrideWith((ref) async => pending),
        notifyTaskHandoversProvider.overrideWith((ref) async => enabled),
        callEntryHasActiveCallProvider.overrideWith(
          (ref) => ref.watch(_onCall),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(_onCall.notifier).set(onCall);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: TaskNotificationsListener()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('ειδοποίηση σε ήρεμη οθόνη: εμφανίζεται', (tester) async {
    await pump(tester, pending: [_notification()]);

    expect(find.text(_kDialogTitle), findsOneWidget);
  });

  testWidgets('τίποτα να δείξει: κανένας διάλογος', (tester) async {
    await pump(tester, pending: const []);

    expect(find.text(_kDialogTitle), findsNothing);
  });

  testWidgets('ενεργή κλήση: σιωπά', (tester) async {
    await pump(tester, pending: [_notification()], onCall: true);

    expect(
      find.text(_kDialogTitle),
      findsNothing,
      reason: 'Ο χειριστής μιλά με άνθρωπο — δεν του κόβεται η φόρμα.',
    );
  });

  testWidgets('η κλήση τελειώνει: η κρατημένη εμφανίζεται', (tester) async {
    final container = await pump(
      tester,
      pending: [_notification()],
      onCall: true,
    );
    expect(find.text(_kDialogTitle), findsNothing);

    container.read(_onCall.notifier).set(false);
    await tester.pumpAndSettle();

    expect(
      find.text(_kDialogTitle),
      findsOneWidget,
      reason: 'Η ειδοποίηση κρατήθηκε, δεν χάθηκε.',
    );
  });

  testWidgets('η ρύθμιση είναι κλειστή: σιωπά', (tester) async {
    await pump(tester, pending: [_notification()], enabled: false);

    expect(find.text(_kDialogTitle), findsNothing);
  });

  testWidgets('ποτέ δεύτερος διάλογος πάνω στον πρώτο', (tester) async {
    await pump(tester, pending: [_notification()]);
    expect(find.text(_kDialogTitle), findsOneWidget);

    // Δεύτερος κύκλος του φρουρού όσο ο πρώτος διάλογος στέκει ανοιχτός.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text(_kDialogTitle), findsOneWidget);
  });
}
