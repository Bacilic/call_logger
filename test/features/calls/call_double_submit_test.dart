// Τεστ-φρουροί διπλής υποβολής κλήσης (Άξονας 3, Φάση 4).
//
//   flutter test test/features/calls/call_double_submit_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../test_setup.dart';

const _doubleSubmitMarker = 'DOUBLE_SUBMIT_GUARD';

Future<void> _loadCallsScreen(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: callLoggerTestProviderOverrides(),
        child: const MyApp(),
      ),
    );
    await tester.pump();
    await pumpUntilSettledLong(tester);
    await GoogleFonts.pendingFonts();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(lookupServiceProvider.future);
  });
}

Future<void> _fillValidCallForm(
  WidgetTester tester, {
  required String notesMarker,
  bool enablePending = false,
}) async {
  final phoneField = callLoggerPhoneTextField();
  await tester.tap(phoneField);
  await pumpUntilSettled(tester);
  await tester.enterText(phoneField, kTestPhoneDigits);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
  await tester.pump(const Duration(milliseconds: 450));
  await pumpUntilSettled(tester, steps: 40, step: const Duration(milliseconds: 60));
  await pumpUntilSettledLong(tester);

  final categoryField = find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.labelText?.contains('Κατηγορία') ?? false),
  );
  await tester.tap(categoryField);
  await pumpUntilSettled(tester);
  await tester.enterText(categoryField, kTestCategoryName);
  await pumpUntilSettled(tester);

  final notesFinder = find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.hintText?.contains('Σημειώσεις') ?? false),
  );
  await tester.tap(notesFinder);
  await pumpUntilSettled(tester);
  await tester.enterText(notesFinder, '$notesMarker $kTestHistorySearchMarker');
  await pumpUntilSettled(tester);

  if (enablePending) {
    final checkboxFinder = find.byType(Checkbox);
    expect(checkboxFinder, findsWidgets);
    await tester.tap(checkboxFinder.first);
    await pumpUntilSettled(tester);
  }

  final submitFinder = find.widgetWithText(ElevatedButton, 'Καταγραφή');
  expect(
    tester.widget<ElevatedButton>(submitFinder).onPressed,
    isNotNull,
    reason: 'Το κουμπί Καταγραφή πρέπει να είναι ενεργό πριν τη διπλή υποβολή',
  );
}

Future<int> _countCallsWithMarker(String marker) async {
  final db = await DatabaseHelper.instance.database;
  final repo = CallsRepository(db);
  final rows = await repo.getHistoryCalls(keyword: marker);
  return rows.length;
}

Future<int> _countTasksForMarker(String marker) async {
  final db = await DatabaseHelper.instance.database;
  final repo = CallsRepository(db);
  final calls = await db.query(
    'calls',
    where: 'issue LIKE ? AND COALESCE(is_deleted, 0) = 0',
    whereArgs: ['%$marker%'],
  );
  var total = 0;
  for (final call in calls) {
    total += await repo.getTasksCountLinkedToCall(call['id'] as int);
  }
  return total;
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Διπλή υποβολή κλήσης (τεστ-φρουρός)', () {
    setUpAll(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      LookupService.instance.resetForReload();
      await LookupService.instance.loadFromDatabase();
    });

    setUp(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('tasks');
      await db.delete('calls');
      await db.delete('audit_log');
    });

    testWidgets(
      'διπλό γρήγορο tap στο Καταγραφή → ακριβώς 1 εγγραφή κλήσης',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _loadCallsScreen(tester);
        await _fillValidCallForm(tester, notesMarker: _doubleSubmitMarker);

        final submitFinder = find.widgetWithText(ElevatedButton, 'Καταγραφή');
        await tester.tap(submitFinder);
        await tester.tap(submitFinder);
        await tester.pump();

        await tester.runAsync(() async {
          await pumpUntilSettledLong(tester);
        });
        await flushCallLoggerSqfliteLockTimers(tester);

        final callCount = await tester.runAsync(
          () => _countCallsWithMarker(_doubleSubmitMarker),
        );
        expect(callCount, 1, reason: 'Πρέπει να αποθηκευτεί ακριβώς μία κλήση');

        final taskCount = await tester.runAsync(
          () => _countTasksForMarker(_doubleSubmitMarker),
        );
        expect(taskCount, 0, reason: 'Χωρίς εκκρεμότητα δεν δημιουργείται task');
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    testWidgets(
      'τριπλό γρήγορο tap στο Καταγραφή → ακριβώς 1 εγγραφή κλήσης',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _loadCallsScreen(tester);
        await _fillValidCallForm(
          tester,
          notesMarker: '${_doubleSubmitMarker}_TRIPLE',
        );

        final submitFinder = find.widgetWithText(ElevatedButton, 'Καταγραφή');
        await tester.tap(submitFinder);
        await tester.tap(submitFinder);
        await tester.tap(submitFinder);
        await tester.pump();

        await tester.runAsync(() async {
          await pumpUntilSettledLong(tester);
        });
        await flushCallLoggerSqfliteLockTimers(tester);

        final callCount = await tester.runAsync(
          () => _countCallsWithMarker('${_doubleSubmitMarker}_TRIPLE'),
        );
        expect(callCount, 1, reason: 'Πρέπει να αποθηκευτεί ακριβώς μία κλήση');
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    testWidgets(
      'διπλή ταυτόχρονη κλήση submitCall → 1 κλήση και 1 εκκρεμότητα',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _loadCallsScreen(tester);
        final marker = '${_doubleSubmitMarker}_PENDING';
        await _fillValidCallForm(
          tester,
          notesMarker: marker,
          enablePending: true,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        expect(container.read(callEntryProvider).isPending, isTrue);

        final results = await tester.runAsync(() async {
          final notifier = container.read(callEntryProvider.notifier);
          final futures = <Future<bool>>[
            notifier.submitCall(),
            notifier.submitCall(),
          ];
          return Future.wait(futures);
        });
        expect(results, [true, false]);

        await tester.pump();
        await flushCallLoggerSqfliteLockTimers(tester);

        final callCount = await tester.runAsync(
          () => _countCallsWithMarker(marker),
        );
        expect(callCount, 1, reason: 'Μία κλήση με εκκρεμότητα');

        final taskCount = await tester.runAsync(
          () => _countTasksForMarker(marker),
        );
        expect(taskCount, 1, reason: 'Μία εκκρεμότητα από τη μοναδική κλήση');
      },
      semanticsEnabled: false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
