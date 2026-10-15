import 'dart:async';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/services/app_close_controller.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:call_logger/core/widgets/app_shortcuts.dart';
import 'package:call_logger/core/widgets/main_shell.dart';
import 'package:call_logger/core/widgets/shutdown_progress_screen.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/provider/calls_dashboard_providers.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

/// Ελέγχει ότι η ροή κλεισίματος εκτελεί τα βήματα με τη σωστή σειρά.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ροή κλεισίματος AppShortcuts', () {
    test(
      'η ροή κλεισίματος εκτελεί τα βήματα με τη σωστή σειρά και τερματίζει τελευταία',
      () async {
        final order = <String>[];
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

        expect(terminateCalled, isTrue);
        expect(
          order,
          ['persist', 'wal', 'backup', 'closeDb', 'crashLog', 'terminate'],
          reason: greekExpectMsg(
            'Η σειρά των βημάτων τερματισμού είναι δεσμευτική',
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
            child: MaterialApp(home: _CloseHarness(coordinator: coordinator)),
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

  /// Μετρημένο 14/10/2026 με σβηστό διακομιστή: το κλείσιμο ξανάστηνε την
  /// κύρια οθόνη από την αρχή, και το στήσιμό της (ανάγνωση του αρχείου της
  /// βάσης στο δίκτυο) πάγωσε την εφαρμογή για 56 δευτερόλεπτα.
  group('το κλείσιμο στο πραγματικό κέλυφος', () {
    registerCallLoggerIsolatedDatabaseHooks();

    setUpAll(() async {
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      appCloseController.resetForTesting();
    });

    tearDown(appCloseController.resetForTesting);

    testWidgets('η κύρια οθόνη δεν ξαναστήνεται όταν ξεκινά το κλείσιμο', (
      tester,
    ) async {
      final path = (await DatabaseHelper.instance.database).path;
      final hang = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...callLoggerTestProviderOverrides(),
            globalRecentCallsProvider.overrideWith(
              (ref) async => const <CallModel>[],
            ),
            globalPendingTasksCountProvider.overrideWith((ref) async => 0),
          ],
          child: MaterialApp(
            home: AppShortcuts(
              initialDatabaseResult: DatabaseInitResult.success(path),
              initialIsLocalDevMode: false,
              shutdownCoordinatorFactory: () => ShutdownCoordinator(
                persistWindowBounds: () => hang.future,
                walCheckpoint: () async {},
                exitBackup: () async {},
                closeConnection: () async {},
                closeCrashLog: () async {},
                terminate: () {},
                delay: (_) => Completer<void>().future,
              ),
              shutdownTraceFactory: () async => null,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final before = tester.state(find.byType(MainShell));

      appCloseController.handleCloseRequest();
      await tester.pump();

      expect(
        identical(tester.state(find.byType(MainShell)), before),
        isTrue,
        reason: greekExpectMsg(
          'Η κύρια οθόνη μένει όπως ήταν· στήσιμο από την αρχή ξανατρέχει '
          'τη δουλειά της εκκίνησης τη στιγμή που η βάση ίσως λείπει',
        ),
      );

      hang.complete();
      await tester.pump(const Duration(seconds: 11));
    });
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
