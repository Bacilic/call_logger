// Widget tests: γρήγορη καταγραφή κλήσης — FAB (όχι AppBar icon).
//
//   flutter test test/features/calls/quick_call_dialog_test.dart

import 'package:call_logger/core/providers/history_audit_immersive_provider.dart';
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

import '../../test_reporter.dart';
import '../../test_setup.dart';


Future<void> _pumpCallLoggerApp(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...callLoggerTestProviderOverrides(),
          showQuickCallFabProvider.overrideWith((ref) async => true),
          enableSpellCheckProvider.overrideWith((ref) async => true),
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

ProviderContainer _appContainer(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Finder _quickCallFab() => find.byKey(QuickCallTrigger.triggerKey);

Finder _quickCallDialog() => find.byKey(const ValueKey('quick_call_dialog'));

bool _isQuickCallDialogFlashActive(WidgetTester tester) {
  // Flash στο backdrop του DialogOutsideTapHintScope (όχι μέσα στο TapRegion του dialog).
  final backdropFinder = find.byKey(const ValueKey('dialog_flash_backdrop'));
  if (backdropFinder.evaluate().isEmpty) return false;
  final container = tester.widget<AnimatedContainer>(backdropFinder);
  final fg = container.foregroundDecoration;
  if (fg is! BoxDecoration) return false;
  final border = fg.border;
  if (border is! Border) return false;
  return border.top.color != Colors.transparent;
}

Future<void> _goToHistory(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav_rail_history')));
  await pumpUntilSettled(tester);
  expect(find.text('Ιστορικό Κλήσεων'), findsOneWidget);
}

Future<void> _goToHistoryImmersive(WidgetTester tester) async {
  await _goToHistory(tester);
  _appContainer(tester)
      .read(historyAuditImmersiveProvider.notifier)
      .setTrue();
  await pumpUntilSettled(tester, steps: 25);
  expect(_quickCallFab(), findsOneWidget);
}

Future<void> _invokeQuickCaptureIntent(WidgetTester tester) async {
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(MainShell));
    Actions.invoke(ctx, const QuickCaptureIntent());
  });
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilSettled(tester, steps: 25);
}

Future<void> _dismissQuickCallDialog(WidgetTester tester) async {
  final dialog = _quickCallDialog();
  if (dialog.evaluate().isEmpty) return;
  await tester.tap(
    find.descendant(of: dialog, matching: find.byTooltip('Κλείσιμο')),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilSettled(tester);
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Γρήγορη καταγραφή κλήσης (widget)', () {
    setUpAll(() async {
      await seedTestCallRowForHistorySearch();
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    testWidgets(
      'Ιστορικό με rail: χωρίς FAB, η συντόμευση ανοίγει διάλογο',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        addTearDown(() async {
          await _dismissQuickCallDialog(tester);
        });

        await _pumpCallLoggerApp(tester);
        await _goToHistory(tester);

        expect(_quickCallFab(), findsNothing);

        await _invokeQuickCaptureIntent(tester);
        expect(_quickCallDialog(), findsOneWidget);

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'Immersive (ιστορικό/λεξικό): εμφανίζεται υπτάμενο κουμπί FAB',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        addTearDown(() async {
          await _dismissQuickCallDialog(tester);
        });

        await _pumpCallLoggerApp(tester);
        await _goToHistoryImmersive(tester);

        expect(
          _quickCallFab(),
          findsOneWidget,
          reason: greekExpectMsg(
            'Σε immersive προβολή (ιστορικό/λεξικό) πρέπει FAB γρήγορης κλήσης',
          ),
        );

        await tester.tap(_quickCallFab());
        await pumpUntilSettled(tester);
        expect(_quickCallDialog(), findsOneWidget);

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'δεύτερο άνοιγμα (FAB + συντόμευση) δεν στοιβάζει διάλογο — flash στον υπάρχοντα',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        addTearDown(() async {
          await _dismissQuickCallDialog(tester);
        });

        await _pumpCallLoggerApp(tester);
        await _goToHistoryImmersive(tester);

        await tester.tap(_quickCallFab());
        await pumpUntilSettled(tester);
        expect(_quickCallDialog(), findsOneWidget);

        await _invokeQuickCaptureIntent(tester);
        await tester.pump(const Duration(milliseconds: 150));
        expect(
          _quickCallDialog(),
          findsOneWidget,
          reason: greekExpectMsg(
            'Δεύτερο άνοιγμα δεν πρέπει να ανοίξει δεύτερο QuickCallDialog',
          ),
        );
        expect(
          _isQuickCallDialogFlashActive(tester),
          isTrue,
          reason: greekExpectMsg(
            'Δεύτερο άνοιγμα πρέπει να αναβοσβήνει τον ήδη ανοιχτό διάλογο',
          ),
        );

        await _invokeQuickCaptureIntent(tester);
        expect(
          _quickCallDialog(),
          findsOneWidget,
          reason: greekExpectMsg(
            'Συντόμευση με ήδη ανοιχτό διάλογο δεν πρέπει να στοιβάξει δεύτερο',
          ),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'Ctrl+Alt+L δεν ανοίγει QuickCallDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        await _goToHistory(tester);

        for (final key in [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.keyL,
        ]) {
          await tester.sendKeyDownEvent(key);
        }
        await tester.pump();
        for (final key in [
          LogicalKeyboardKey.keyL,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.controlLeft,
        ]) {
          await tester.sendKeyUpEvent(key);
        }
        await tester.pump(const Duration(milliseconds: 300));

        expect(_quickCallDialog(), findsNothing);
        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );
  });
}
