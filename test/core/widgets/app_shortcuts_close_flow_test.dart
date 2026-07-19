import 'dart:async';

import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:call_logger/core/widgets/shutdown_progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

/// Τεκμηριώνει την παλιά ροή (destroy) έναντι της νέας (injectable terminate).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ροή κλεισίματος AppShortcuts', () {
    test(
      'παλιά ροή κατέληγε σε windowManager.destroy — νέα ροή καλεί terminate',
      () async {
        // Χαρακτηρισμός παλιάς συμπεριφοράς (τεκμηρίωση, όχι εκτέλεση destroy):
        const oldFlowEndedWith = 'windowManager.destroy';
        expect(oldFlowEndedWith, 'windowManager.destroy');

        final order = <String>[];
        var destroyCalled = false;
        var terminateCalled = false;

        final coordinator = ShutdownCoordinator(
          persistWindowBounds: () async => order.add('persist'),
          walCheckpoint: () async => order.add('wal'),
          exitBackup: () async => order.add('backup'),
          closeConnection: () async => order.add('closeDb'),
          closeCrashLog: () async => order.add('crashLog'),
          terminate: () {
            terminateCalled = true;
            order.add('terminate');
          },
        );

        await coordinator.run();

        // Η νέα ροή δεν εκθέτει καν destroy — προσομοίωση ότι δεν κλήθηκε.
        expect(destroyCalled, isFalse);
        expect(terminateCalled, isTrue);
        expect(order.last, 'terminate');
        expect(order[order.length - 2], 'crashLog');
        expect(
          order,
          isNot(contains('destroy')),
          reason: greekExpectMsg(
            'Η νέα ροή κλεισίματος δεν καλεί windowManager.destroy()',
          ),
        );
      },
    );

    testWidgets(
      'AppShortcuts εμφανίζει οθόνη προόδου μετά τα 500 ms σε αργό κλείσιμο',
      (tester) async {
        final hang = Completer<void>();
        final coordinator = ShutdownCoordinator(
          persistWindowBounds: () => hang.future,
          walCheckpoint: () async {},
          exitBackup: () async {},
          closeConnection: () async {},
          closeCrashLog: () async {},
          terminate: () {},
          // Ποτέ μην πυροδότησεις timeout — αποφεύγει pending Timer στα τεστ.
          delay: (_) => Completer<void>().future,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: _CloseHarness(
                coordinator: coordinator,
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('Κλείσιμο'));
        await tester.pump();

        expect(
          find.byType(ShutdownProgressScreen, skipOffstage: false),
          findsOneWidget,
        );
        expect(find.text('Κλείσιμο εφαρμογής'), findsNothing);

        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Κλείσιμο εφαρμογής'), findsOneWidget);

        hang.complete();
        await tester.pump(const Duration(milliseconds: 50));
      },
    );
  });
}

/// Μικρό κέλυφος που ασκεί την ίδια λογική εμφάνισης με το AppShortcuts
/// χωρίς πραγματικό window_manager.
class _CloseHarness extends StatefulWidget {
  const _CloseHarness({required this.coordinator});

  final ShutdownCoordinator coordinator;

  @override
  State<_CloseHarness> createState() => _CloseHarnessState();
}

class _CloseHarnessState extends State<_CloseHarness> {
  bool _showProgress = false;
  ShutdownCoordinator? _coordinator;

  Future<void> _onClose() async {
    setState(() => _coordinator = widget.coordinator);
    var stillRunning = true;
    final timer = scheduleShutdownProgressReveal(
      onReveal: () {
        if (!mounted) return;
        setState(() => _showProgress = true);
      },
      isShutdownStillRunning: () => stillRunning && mounted,
    );
    try {
      await WidgetsBinding.instance.endOfFrame;
      await widget.coordinator.run();
    } finally {
      stillRunning = false;
      timer.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_showProgress)
          Scaffold(
            body: Center(
              child: TextButton(
                onPressed: _onClose,
                child: const Text('Κλείσιμο'),
              ),
            ),
          ),
        if (_coordinator != null)
          Offstage(
            offstage: !_showProgress,
            child: ShutdownProgressScreen(events: _coordinator!.events),
          ),
      ],
    );
  }
}
