// Έλεγχος: μετά από έμμεσες/άμεσες mutations εκκρεμοτήτων, τα analytics και
// sibling providers ανανεώνονται χωρίς χειροκίνητο refresh.
//
//   flutter test test/features/tasks/task_analytics_refresh_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/provider/call_mutation_refresh.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/providers/task_analytics_date_provider.dart';
import 'package:call_logger/features/tasks/providers/task_analytics_provider.dart';
import 'package:call_logger/features/tasks/providers/task_service_provider.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Ref? _capturedRef;

final _refCaptureProvider = Provider<int>((ref) {
  _capturedRef = ref;
  return 0;
});

Future<ProviderContainer> _taskTestContainer() async {
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  container.read(_refCaptureProvider);
  await container.read(taskAnalyticsDateProvider.future);
  return container;
}

Future<int> _insertOrphanPendingCall() async {
  final db = await DatabaseHelper.instance.database;
  return db.insert('calls', {
    'phone_text': kTestPhoneDigits,
    'issue': '$kTestHistorySearchMarker orphan analytics',
    'status': 'pending',
    'is_deleted': 0,
  });
}

Future<void> _insertExtraTaskDirectly() async {
  final db = await DatabaseHelper.instance.database;
  final now = DateTime.now();
  final iso = now.toIso8601String();
  await db.insert('tasks', {
    'title': 'Extra task DB only',
    'description': 'direct insert',
    'due_date': iso,
    'status': 'open',
    'origin': Task.originManualFab,
    'created_at': iso,
    'updated_at': iso,
    'is_deleted': 0,
  });
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Task analytics refresh — Δέσμη Β', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
    });

    test(
      'invalidateTaskListProviders ανανεώνει taskAnalyticsProvider μετά έμμεση δημιουργία',
      () async {
        final container = await _taskTestContainer();
        container.listen(taskAnalyticsProvider, (_, _) {});

        await container.read(taskAnalyticsProvider.future);
        expect(
          container.read(taskAnalyticsProvider).requireValue.createdInRangeCount,
          0,
        );

        await container.read(taskServiceProvider).createFromCall(
              callId: null,
              callerName: 'Έμμεση εκκρεμότητα',
              description: 'Δοκιμή analytics refresh',
              callDate: DateTime.now(),
            );

        invalidateTaskListProviders(_capturedRef!);

        final analyticsAfter =
            await container.read(taskAnalyticsProvider.future);
        expect(
          analyticsAfter.createdInRangeCount,
          1,
          reason:
              'taskAnalyticsProvider πρέπει να δείχνει νέα εκκρεμότητα χωρίς χειροκίνητο refresh',
        );
        expect(analyticsAfter.activeNowCount, 1);

        container.dispose();
      },
    );

    test(
      'TasksNotifier.updateTask ανανεώνει analytics, totalTasksCount και orphanCalls',
      () async {
        final container = await _taskTestContainer();
        final orphanCallId = await _insertOrphanPendingCall();

        final taskId = await container.read(taskServiceProvider).createFromCall(
              callId: null,
              callerName: kTestUserFirstName,
              description: 'Ανοικτή προς κλείσιμο',
              callDate: DateTime.now(),
            );

        await container.read(tasksProvider.notifier).refresh();

        container.listen(taskAnalyticsProvider, (_, _) {});
        container.listen(totalTasksCountProvider, (_, _) {});
        container.listen(orphanCallsProvider, (_, _) {});

        await container.read(taskAnalyticsProvider.future);
        await container.read(totalTasksCountProvider.future);
        await container.read(orphanCallsProvider.future);

        expect(
          container.read(taskAnalyticsProvider).requireValue.activeNowCount,
          1,
        );
        expect(container.read(totalTasksCountProvider).requireValue, 1);
        expect(container.read(orphanCallsProvider).requireValue.length, 1);

        await _insertExtraTaskDirectly();

        final tasks = await container.read(tasksProvider.future);
        final openTask = tasks.firstWhere((t) => t.id == taskId);

        await container.read(tasksProvider.notifier).updateTask(
              openTask.copyWith(
                callId: orphanCallId,
                status: TaskStatus.closed.toDbValue,
                solutionNotes: 'Ολοκληρώθηκε',
              ),
            );

        final analyticsAfter =
            await container.read(taskAnalyticsProvider.future);
        final totalAfter =
            await container.read(totalTasksCountProvider.future);
        final orphansAfter =
            await container.read(orphanCallsProvider.future);
        final directTotal =
            await container.read(taskServiceProvider).getTotalTaskCount();

        expect(
          analyticsAfter.activeNowCount,
          1,
          reason:
              'Μία ανοικτή (extra DB) — η κλεισμένη δεν μετράει στο activeNow',
        );
        expect(analyticsAfter.closedInRangeCount, 1);
        expect(
          totalAfter,
          directTotal,
          reason:
              'totalTasksCountProvider πρέπει να ξαναδιαβάσει τη βάση (2 εγγραφές) χωρίς χειροκίνητο refresh',
        );
        expect(totalAfter, 2);
        expect(
          orphansAfter,
          isEmpty,
          reason:
              'orphanCallsProvider πρέπει να αδειάσει μετά τη σύνδεση task–κλήση',
        );

        container.dispose();
      },
    );
  });
}
