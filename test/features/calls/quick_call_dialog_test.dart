// Widget tests: γρήγορη καταγραφή κλήσης — FAB (όχι AppBar icon).
//
//   flutter test test/features/calls/quick_call_dialog_test.dart

import 'package:call_logger/core/providers/history_audit_immersive_provider.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/widgets/main_shell.dart';
import 'package:call_logger/core/widgets/quick_call_fab.dart';
import 'package:call_logger/core/widgets/app_keyboard_shortcuts.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/quick_call_session_provider.dart';
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
        child: const MyApp(showStartupScreens: false),
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

Future<void> _goToHistory(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav_rail_history')));
  await pumpUntilSettled(tester);
  expect(find.text('Ιστορικό Κλήσεων'), findsOneWidget);
}

Future<void> _goToHistoryImmersive(WidgetTester tester) async {
  await _goToHistory(tester);
  _appContainer(tester).read(historyAuditImmersiveProvider.notifier).setTrue();
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

Finder _minimizedPhone() => find.byKey(QuickCallTrigger.minimizedKey);

Finder _quickPhoneField() => find.descendant(
  of: _quickCallDialog(),
  matching: callLoggerPhoneTextField(),
);

Future<void> _typeQuickPhone(WidgetTester tester) async {
  await tester.tap(_quickPhoneField());
  await pumpUntilSettled(tester);
  await tester.enterText(_quickPhoneField(), kTestPhoneDigits);
  await pumpUntilSettled(tester);
}

Future<void> _tapInQuickDialog(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilSettled(tester);
}

/// Στο τέλος του τεστ δεν μένει γρήγορη καταγραφή: ούτε ανοιχτή, ούτε
/// ελαχιστοποιημένη.
Future<void> _endQuickCall(WidgetTester tester) async {
  if (_quickCallDialog().evaluate().isNotEmpty) {
    await _tapInQuickDialog(tester, const ValueKey('quick_call_close'));
    final confirm = find.widgetWithText(TextButton, 'Κλείσιμο');
    if (confirm.evaluate().isNotEmpty) await tester.tap(confirm);
    await tester.pump(const Duration(milliseconds: 300));
  }
  _appContainer(tester).read(quickCallSessionProvider.notifier).end();
  await pumpUntilSettled(tester);
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

    testWidgets('Ιστορικό με rail: χωρίς FAB, η συντόμευση ανοίγει διάλογο', (
      tester,
    ) async {
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
    }, semanticsEnabled: false);

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
      'δεύτερο άνοιγμα (FAB + συντόμευση) δεν στοιβάζει δεύτερο διάλογο',
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

    testWidgets('Ctrl+Alt+L δεν ανοίγει QuickCallDialog', (tester) async {
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
    }, semanticsEnabled: false);

    testWidgets(
      'επιτυχής καταγραφή: ο διάλογος κλείνει και το μήνυμα επιτυχίας μένει ορατό',
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
        await _invokeQuickCaptureIntent(tester);
        expect(_quickCallDialog(), findsOneWidget);

        final phoneField = find.descendant(
          of: _quickCallDialog(),
          matching: callLoggerPhoneTextField(),
        );
        await tester.tap(phoneField);
        await pumpUntilSettled(tester);
        await tester.enterText(phoneField, kTestPhoneDigits);
        await pumpUntilSettled(tester);

        final submitFinder = find.descendant(
          of: _quickCallDialog(),
          matching: find.widgetWithText(ElevatedButton, 'Καταγραφή'),
        );
        expect(
          tester.widget<ElevatedButton>(submitFinder).onPressed,
          isNotNull,
        );

        // Η υποβολή ανοίγει συναλλαγή sqflite· έξω από `runAsync` η απάντηση
        // του FFI δεν φτάνει ποτέ και το τεστ κρεμάει.
        await tester.runAsync(() async {
          await tester.tap(submitFinder);
          for (
            var i = 0;
            i < 20 && _quickCallDialog().evaluate().isNotEmpty;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
          }
        });
        await tester.pump(const Duration(milliseconds: 500));
        await pumpUntilSettled(tester);

        expect(_quickCallDialog(), findsNothing);
        expect(
          find.text('Κλήση αποθηκεύτηκε (γρήγορη καταγραφή)'),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το μήνυμα επιτυχίας πρέπει να επιζεί του κλεισίματος του διαλόγου',
          ),
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'ελαχιστοποίηση: ο διάλογος κατεβαίνει σε τηλέφωνο που χτυπά, και η '
      'επαναφορά φέρνει πίσω ό,τι γράφτηκε',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        await _goToHistory(tester);
        await _invokeQuickCaptureIntent(tester);
        await _typeQuickPhone(tester);

        await _tapInQuickDialog(tester, const ValueKey('quick_call_minimize'));
        expect(_quickCallDialog(), findsNothing);
        expect(_minimizedPhone(), findsOneWidget);

        await tester.tap(_minimizedPhone());
        await pumpUntilSettled(tester);
        expect(_quickCallDialog(), findsOneWidget);
        expect(_minimizedPhone(), findsNothing);
        expect(
          tester.widget<TextField>(_quickPhoneField()).controller?.text,
          kTestPhoneDigits,
          reason: greekExpectMsg('Η επαναφορά κρατά το τηλέφωνο που γράφτηκε'),
        );

        await _endQuickCall(tester);
        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets('οθόνη Κλήσεων: η συντόμευση ανοίγει τη γρήγορη καταγραφή και '
        'επαναφέρει την ελαχιστοποιημένη αντί να ανοίξει δεύτερη', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpCallLoggerApp(tester);
      await _invokeQuickCaptureIntent(tester);
      expect(_quickCallDialog(), findsOneWidget);
      await _typeQuickPhone(tester);

      await _tapInQuickDialog(tester, const ValueKey('quick_call_minimize'));
      expect(_minimizedPhone(), findsOneWidget);

      await _invokeQuickCaptureIntent(tester);
      expect(_quickCallDialog(), findsOneWidget);
      expect(
        tester.widget<TextField>(_quickPhoneField()).controller?.text,
        kTestPhoneDigits,
        reason: greekExpectMsg(
          'Η συντόμευση επαναφέρει την ίδια καταγραφή, όχι καινούρια',
        ),
      );

      await _endQuickCall(tester);
      await flushCallLoggerSqfliteLockTimers(tester);
    }, semanticsEnabled: false);

    testWidgets(
      'το Χ με γραμμένη καταγραφή ρωτά: «Επιστροφή» την κρατά, «Κλείσιμο» '
      'τη σβήνει',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        await _goToHistory(tester);
        await _invokeQuickCaptureIntent(tester);
        await _typeQuickPhone(tester);

        await _tapInQuickDialog(tester, const ValueKey('quick_call_close'));
        expect(find.text('Ό,τι γράψατε θα χαθεί.'), findsOneWidget);
        await tester.tap(find.text('Επιστροφή'));
        await pumpUntilSettled(tester);
        expect(_quickCallDialog(), findsOneWidget);
        expect(
          tester.widget<TextField>(_quickPhoneField()).controller?.text,
          kTestPhoneDigits,
        );

        await _tapInQuickDialog(tester, const ValueKey('quick_call_close'));
        await tester.tap(find.widgetWithText(TextButton, 'Κλείσιμο'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await pumpUntilSettled(tester);
        expect(_quickCallDialog(), findsNothing);
        expect(_minimizedPhone(), findsNothing);
        expect(
          _appContainer(tester).read(quickCallSessionProvider),
          QuickCallPhase.closed,
        );

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'οθόνη Κλήσεων με κλήση σε εξέλιξη: η πληκτρολόγηση πηγαίνει στη γρήγορη '
      'καταγραφή, όχι στην κύρια φόρμα πίσω της',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        final mainPhone = callLoggerPhoneTextField().first;
        await tester.tap(mainPhone);
        await pumpUntilSettled(tester);
        await tester.enterText(mainPhone, kTestPhoneDigits);
        await pumpUntilSettled(tester);

        // Το άνοιγμα παίρνει την εστίαση· η κύρια φόρμα κλειδώνει το τηλέφωνο,
        // βρίσκει τον καλούντα και αλλάζει όψη πίσω από τον διάλογο.
        await _invokeQuickCaptureIntent(tester);
        await pumpUntilSettledLong(tester);
        expect(_quickCallDialog(), findsOneWidget);

        tester.testTextInput.enterText('5067');
        await pumpUntilSettled(tester);

        expect(
          tester.widget<TextField>(_quickPhoneField()).controller?.text,
          '5067',
          reason: greekExpectMsg('Τα ψηφία ανήκουν στη γρήγορη καταγραφή'),
        );
        final mainTexts = tester
            .widgetList<TextField>(callLoggerPhoneTextField())
            .map((f) => f.controller?.text)
            .toList();
        expect(
          mainTexts,
          contains(kTestPhoneDigits),
          reason: greekExpectMsg(
            'Το τηλέφωνο της κύριας φόρμας μένει ανέγγιχτο',
          ),
        );

        await _endQuickCall(tester);
        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets('το Χ σε άδεια καταγραφή κλείνει χωρίς ερώτηση', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpCallLoggerApp(tester);
      await _goToHistory(tester);
      await _invokeQuickCaptureIntent(tester);

      await _tapInQuickDialog(tester, const ValueKey('quick_call_close'));
      expect(find.text('Ό,τι γράψατε θα χαθεί.'), findsNothing);
      expect(_quickCallDialog(), findsNothing);

      await flushCallLoggerSqfliteLockTimers(tester);
    }, semanticsEnabled: false);

    testWidgets(
      'πέρασμα από τα πεδία χωρίς να γραφτεί τίποτα, ελαχιστοποίηση και '
      'επαναφορά: το Χ κλείνει πάλι χωρίς ερώτηση',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _pumpCallLoggerApp(tester);
        await _goToHistory(tester);
        await _invokeQuickCaptureIntent(tester);

        await tester.tap(_quickPhoneField());
        await pumpUntilSettled(tester);
        for (var i = 0; i < 4; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await pumpUntilSettled(tester);
        }
        await _tapInQuickDialog(tester, const ValueKey('quick_call_minimize'));
        await _invokeQuickCaptureIntent(tester);
        expect(_quickCallDialog(), findsOneWidget);

        await _tapInQuickDialog(tester, const ValueKey('quick_call_close'));
        expect(find.text('Ό,τι γράψατε θα χαθεί.'), findsNothing);
        expect(_quickCallDialog(), findsNothing);

        await flushCallLoggerSqfliteLockTimers(tester);
      },
      semanticsEnabled: false,
    );
  });
}
