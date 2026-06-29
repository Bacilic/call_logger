// Έλεγχος πραγματικής συντόμευσης Ctrl+Shift+N (EN/EL) — όχι μόνο Actions.invoke.
//
//   flutter test test/features/calls/quick_call_keyboard_shortcut_test.dart

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/widgets/main_shell.dart';
import 'package:call_logger/core/widgets/quick_call_fab.dart';
import 'package:call_logger/core/widgets/quick_call_shortcuts.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Finder _quickCallDialog() => find.byKey(const ValueKey('quick_call_dialog'));

Future<void> _pumpCallLoggerApp(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...callLoggerTestProviderOverrides(),
          showQuickCallFabProvider.overrideWith((ref) async => true),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();
    await pumpUntilSettledLong(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(lookupServiceProvider.future);
  });
}

Future<void> _goToTasks(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav_rail_tasks')));
  await pumpUntilSettled(tester);
  expect(find.text('Εκκρεμότητες'), findsWidgets);
}

Future<void> _sendCtrlShiftN(WidgetTester tester) async {
  for (final key in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.keyN,
  ]) {
    await tester.sendKeyDownEvent(key, platform: 'windows');
  }
  await tester.pump();
  for (final key in [
    LogicalKeyboardKey.keyN,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.controlLeft,
  ]) {
    await tester.sendKeyUpEvent(key, platform: 'windows');
  }
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilSettled(tester, steps: 25);
}

Future<void> _sendCtrlGreekNu(WidgetTester tester) async {
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    platform: 'windows',
  );
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.keyN,
    character: 'Ν',
    platform: 'windows',
  );
  await tester.pump();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN, platform: 'windows');
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    platform: 'windows',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilSettled(tester, steps: 25);
}

Future<void> _goToDirectoryMiscTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav_rail_directory')));
  await pumpUntilSettled(tester);
  await tester.tap(find.text('Διάφορα'));
  await pumpUntilSettled(tester);
  expect(find.text('Κατηγορίες Προβλήματος'), findsOneWidget);
}

Future<void> _goToDatabase(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav_rail_database')));
  await tester.runAsync(() async {
    for (var i = 0; i < 80; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 16));
      if (find.text('Στατιστικά Βάσης Δεδομένων').evaluate().isNotEmpty) {
        return;
      }
    }
  });
  await pumpUntilSettled(tester, steps: 25);
  expect(find.text('Στατιστικά Βάσης Δεδομένων'), findsOneWidget);
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Συντόμευση πληκτρολογίου γρήγορης κλήσης', () {
    setUpAll(() async {
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    testWidgets(
      'Minimal Shortcuts+Actions+Focus: Ctrl+Shift+N ενεργοποιεί intent',
      (tester) async {
        var invoked = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Shortcuts(
              shortcuts: quickCallShortcuts,
              child: Actions(
                actions: <Type, Action<Intent>>{
                  QuickCaptureIntent: CallbackAction<QuickCaptureIntent>(
                    onInvoke: (QuickCaptureIntent intent) {
                      invoked = true;
                      return null;
                    },
                  ),
                },
                child: const Focus(
                  autofocus: true,
                  child: SizedBox(width: 200, height: 200),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.controlLeft,
          platform: 'windows',
        );
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.shiftLeft,
          platform: 'windows',
        );
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.keyN,
          platform: 'windows',
        );
        await tester.pump();

        expect(invoked, isTrue);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN, platform: 'windows');
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.shiftLeft,
          platform: 'windows',
        );
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.controlLeft,
          platform: 'windows',
        );
      },
    );

    testWidgets(
      'AppShortcuts δομή χωρίς Focus: Ctrl+Shift+N δεν ενεργοποιεί intent',
      (tester) async {
        var invoked = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Shortcuts(
              shortcuts: quickCallShortcuts,
              child: Actions(
                actions: <Type, Action<Intent>>{
                  QuickCaptureIntent: CallbackAction<QuickCaptureIntent>(
                    onInvoke: (QuickCaptureIntent intent) {
                      invoked = true;
                      return null;
                    },
                  ),
                },
                child: Scaffold(
                  body: Row(
                    children: [
                      NavigationRail(
                        selectedIndex: 0,
                        onDestinationSelected: (_) {},
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.home),
                            label: Text('Home'),
                          ),
                        ],
                      ),
                      const Expanded(child: Text('Tasks-like body')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byType(NavigationRail));
        await tester.pump();

        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.controlLeft,
          platform: 'windows',
        );
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.shiftLeft,
          platform: 'windows',
        );
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.keyN,
          platform: 'windows',
        );
        await tester.pump();

        expect(
          invoked,
          isFalse,
          reason: 'Χωρίς Focus(autofocus) τα πλήκτρα δεν φτάνουν στο Shortcuts',
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN, platform: 'windows');
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.shiftLeft,
          platform: 'windows',
        );
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.controlLeft,
          platform: 'windows',
        );
      },
    );

    testWidgets(
      'Εκκρεμότητες: QuickCaptureIntent (χωρίς πληκτρολόγιο) ανοίγει διάλογο',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        await _goToTasks(tester);

        await tester.runAsync(() async {
          final ctx = tester.element(find.byType(MainShell));
          Actions.invoke(ctx, const QuickCaptureIntent());
        });
        await tester.pump(const Duration(milliseconds: 300));
        await pumpUntilSettled(tester, steps: 25);

        expect(_quickCallDialog(), findsOneWidget);

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'Εκκρεμότητες: Ctrl+Shift+N ανοίγει QuickCallDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        await _goToTasks(tester);

        expect(_quickCallDialog(), findsNothing);
        expect(find.byKey(QuickCallTrigger.triggerKey), findsNothing);

        await _sendCtrlShiftN(tester);

        expect(
          _quickCallDialog(),
          findsOneWidget,
          reason: 'Ctrl+Shift+N πρέπει να ανοίγει διάλογο γρήγορης κλήσης '
              'στην οθόνη εκκρεμοτήτων',
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'Κατάλογος Διάφορα: Ctrl+Shift+N ανοίγει QuickCallDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        await _goToDirectoryMiscTab(tester);

        await _sendCtrlShiftN(tester);

        expect(
          _quickCallDialog(),
          findsOneWidget,
          reason: 'Ctrl+Shift+N πρέπει να δουλεύει στην καρτέλα Διάφορα '
              '(χωρίς πίνακα/Focus hover)',
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'Βάση Δεδομένων: Ctrl+Shift+N ανοίγει QuickCallDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        await _goToDatabase(tester);

        await _sendCtrlShiftN(tester);

        expect(
          _quickCallDialog(),
          findsOneWidget,
          reason: 'Ctrl+Shift+N πρέπει να δουλεύει στην οθόνη Βάσης Δεδομένων',
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'Εκκρεμότητες: Ctrl+Ν (ελληνικό CharacterActivator) ανοίγει QuickCallDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        await _goToTasks(tester);

        await _sendCtrlGreekNu(tester);

        expect(
          _quickCallDialog(),
          findsOneWidget,
          reason: 'Ctrl+Ν (ελληνική διάταξη) πρέπει να ανοίγει διάλογο '
              'γρήγορης κλήσης',
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );
  });
}
