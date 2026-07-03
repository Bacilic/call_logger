// Τεστ χαρακτηρισμού πριν τη διάσπαση του main_shell.dart.
//
//   flutter test test/core/widgets/main_shell_split_characterization_test.dart

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/widgets/main_shell.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/calls_screen.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:call_logger/features/tasks/screens/tasks_screen.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<void> _pumpMainShellApp(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...callLoggerTestProviderOverrides(),
          showLampNavProvider.overrideWith((ref) async => true),
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

void _useWideShellViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
}

Finder _tasksNavBadge(WidgetTester tester) {
  return find.ancestor(
    of: find.byKey(const ValueKey('nav_rail_tasks')),
    matching: find.byType(Badge),
  );
}

Future<void> _flushSqfliteLockTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('MainShell split characterization', () {
    setUpAll(() async {
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    testWidgets('όλοι οι προορισμοί πλοήγησης είναι ορατοί στο rail', (
      tester,
    ) async {
      _useWideShellViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpMainShellApp(tester);

      expect(find.byType(MainShell), findsOneWidget);
      for (final key in [
        'nav_rail_calls',
        'nav_rail_tasks',
        'nav_rail_directory',
        'nav_rail_history',
        'nav_rail_lamp',
        'nav_rail_database',
        'nav_rail_dictionary',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
    });

    testWidgets('επιλογή Εκκρεμοτήτων εμφανίζει την οθόνη εκκρεμοτήτων', (
      tester,
    ) async {
      _useWideShellViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpMainShellApp(tester);

      await tester.tap(find.byKey(const ValueKey('nav_rail_tasks')));
      await pumpUntilSettled(tester);

      expect(find.byType(TasksScreen), findsOneWidget);
      expect(find.text('Εκκρεμότητες'), findsWidgets);
      await _flushSqfliteLockTimers(tester);
    });

    testWidgets('εικονίδιο εκκρεμοτήτων δείχνει badge όταν υπάρχουν εκκρεμείς', (
      tester,
    ) async {
      _useWideShellViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...callLoggerTestProviderOverrides(),
              showLampNavProvider.overrideWith((ref) async => true),
              enableSpellCheckProvider.overrideWith((ref) async => true),
              globalPendingTasksCountProvider.overrideWith((ref) async => 4),
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
        await container.read(globalPendingTasksCountProvider.future);
      });
      await pumpUntilSettled(tester);

      final badgeFinder = _tasksNavBadge(tester);
      expect(badgeFinder, findsOneWidget);
      final badge = tester.widget<Badge>(badgeFinder);
      expect(badge.isLabelVisible, isTrue);
      expect((badge.label! as Text).data, '4');
    });

    testWidgets('εναλλαγή προορισμού επιστρέφει στις Κλήσεις', (tester) async {
      _useWideShellViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpMainShellApp(tester);

      await tester.tap(find.byKey(const ValueKey('nav_rail_tasks')));
      await pumpUntilSettled(tester);
      expect(find.byType(TasksScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav_rail_calls')));
      await pumpUntilSettled(tester);
      expect(find.byType(CallsScreen), findsOneWidget);
      expect(find.byType(TasksScreen), findsNothing);
      await _flushSqfliteLockTimers(tester);
    });
  });
}
