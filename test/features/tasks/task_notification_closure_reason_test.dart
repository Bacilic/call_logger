// Ο λόγος του κλεισίματος ταξιδεύει από τη βάση μέχρι την ειδοποίηση.
//
// Δεν προστέθηκε πεδίο: η λύση γράφεται ήδη πάνω στην εκκρεμότητα μέσα στην
// ίδια συναλλαγή με το κλείσιμο. Αυτό που έλειπε ήταν να τη ζητήσει κανείς.
//
//   flutter test test/features/tasks/task_notification_closure_reason_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/task_notifications_repository.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/models/task_notification.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('ο λόγος κλεισίματος φτάνει στον παραλήπτη', () {
    late TasksRepository tasks;
    late TaskNotificationsRepository notifications;

    /// Ο Βλάσης κατέχει την εκκρεμότητα· ο Βασίλης είναι αυτός που την κλείνει.
    const vlasisId = 1;
    const vasilisId = 2;

    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
      tasks = TasksRepository();
      notifications = TaskNotificationsRepository();
      final db = await DatabaseHelper.instance.database;
      // Καθαρή αφετηρία: η απομονωμένη βάση επιβιώνει ανάμεσα στα τεστ, και
      // μια ειδοποίηση του προηγούμενου θα μετρούσε ως αποτέλεσμα του επόμενου.
      await db.delete('task_notifications');
      await db.delete('tasks');
      await db.delete('operators');
      await db.insert('operators', {
        'id': vlasisId,
        'display_name': 'Βλάσης',
        'created_at': DateTime(2026, 9, 1).toIso8601String(),
      });
      await db.insert('operators', {
        'id': vasilisId,
        'display_name': 'Βασίλης',
        'created_at': DateTime(2026, 9, 1).toIso8601String(),
      });
      CurrentOperator.reset();
    });

    tearDown(CurrentOperator.reset);

    Operator profileOf(int id, String name) =>
        Operator(id: id, displayName: name, createdAt: DateTime(2026, 9, 1));

    /// Ο Βλάσης ανοίγει τη ΔΙΚΗ του εκκρεμότητα — κανείς δεν ειδοποιεί τον
    /// εαυτό του, οπότε η ουρά ξεκινά άδεια.
    Future<int> openTaskOwnedByVlasis() async {
      CurrentOperator.activate(profileOf(vlasisId, 'Βλάσης'));
      final id = await tasks.createTask(
        Task(
          title: 'Δεν τυπώνει ο εκτυπωτής του ΤΕΠ',
          dueDate: '2026-09-30',
          status: 'open',
          assignedOperatorId: vlasisId,
        ),
      );
      expect(await notifications.unseenFor(vlasisId), isEmpty);
      return id;
    }

    test('ο Βλάσης μαθαίνει ΓΙΑΤΙ έκλεισε, όχι μόνο ότι έκλεισε', () async {
      final taskId = await openTaskOwnedByVlasis();

      // Ο Βασίλης την κλείνει, γράφοντας τι έκανε.
      CurrentOperator.activate(profileOf(vasilisId, 'Βασίλης'));
      await tasks.closeTask(taskId, 'Αντικαταστάθηκε το τύμπανο');

      final waiting = await notifications.unseenFor(vlasisId);

      expect(waiting, hasLength(1));
      expect(waiting.single.kind, TaskNotificationKind.closed);
      expect(waiting.single.visibleClosureNote, 'Αντικαταστάθηκε το τύμπανο');
    });

    test('κλείσιμο χωρίς λύση δεν επινοεί λόγο', () async {
      final taskId = await openTaskOwnedByVlasis();
      CurrentOperator.activate(profileOf(vasilisId, 'Βασίλης'));
      await tasks.closeTask(taskId, '');

      final waiting = await notifications.unseenFor(vlasisId);

      expect(waiting, hasLength(1));
      expect(waiting.single.visibleClosureNote, isNull);
    });
  });
}
