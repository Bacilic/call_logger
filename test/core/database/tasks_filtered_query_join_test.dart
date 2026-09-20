// Το ερώτημα της λίστας ενώνεται με τις κλήσεις, που έχουν ΟΜΩΝΥΜΕΣ στήλες
// (`status`, `search_index`, `created_at`). Κάθε φίλτρο και κάθε ταξινόμηση
// πρέπει να γράφει `tasks.<στήλη>` — αλλιώς η βάση απαντά «ambiguous column
// name» και η οθόνη μένει για πάντα στο «Φόρτωση εκκρεμοτήτων…».
//
//   flutter test test/core/database/tasks_filtered_query_join_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_lansweeper_repository.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/core/models/owner_filter.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/models/task_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('η λίστα εκκρεμοτήτων με ένωση προς τις κλήσεις', () {
    late TasksRepository repo;
    late Database db;
    late int callId;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('tasks_join_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/join.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('tasks');
      await db.delete('calls');
      repo = TasksRepository();
      callId = await db.insert('calls', {
        'issue': 'Δεν τυπώνει',
        'status': 'completed',
        'lansweeper_main_ticket_id': '6005',
      });
      await repo.createTask(
        Task(
          callId: callId,
          title: 'Από κλήση με αίτημα',
          dueDate: DateTime.now().toIso8601String(),
          status: 'open',
        ),
      );
      await repo.createTask(
        Task(
          title: 'Αυτόνομη',
          dueDate: DateTime.now().toIso8601String(),
          status: 'open',
        ),
      );
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('φιλτράρισμα κατάστασης δεν γίνεται ασαφές', () async {
      final tasks = await repo.getFilteredTasks(
        const TaskFilter(statuses: [TaskStatus.open]),
      );

      expect(tasks, hasLength(2));
    });

    test('αναζήτηση κειμένου δεν γίνεται ασαφής', () async {
      final tasks = await repo.getFilteredTasks(
        const TaskFilter(statuses: [TaskStatus.open], searchQuery: 'αυτόνομη'),
      );

      expect(tasks, hasLength(1));
      expect(tasks.single.title, 'Αυτόνομη');
    });

    test('κάθε ταξινόμηση δουλεύει πάνω στην ένωση', () async {
      for (final option in TaskSortOption.values) {
        final tasks = await repo.getFilteredTasks(
          TaskFilter(statuses: const [TaskStatus.open], sortBy: option),
        );
        expect(tasks, hasLength(2), reason: 'ταξινόμηση ${option.name}');
      }
    });

    test('φίλτρο ευθύνης δουλεύει πάνω στην ένωση', () async {
      final tasks = await repo.getFilteredTasks(
        const TaskFilter(
          statuses: [TaskStatus.open],
          owner: OwnerFilter.unassigned,
        ),
      );

      expect(tasks, isNotEmpty);
    });

    test('η εκκρεμότητα φέρνει μαζί το αίτημα ΤΗΣ ΚΛΗΣΗΣ της', () async {
      final tasks = await repo.getFilteredTasks(
        const TaskFilter(statuses: [TaskStatus.open]),
      );

      final linked = tasks.firstWhere((t) => t.callId == callId);
      final standalone = tasks.firstWhere((t) => t.callId == null);
      expect(linked.linkedCallTicketId, '6005');
      expect(standalone.linkedCallTicketId, isNull);
    });

    test('το αίτημα της κλήσης ΔΕΝ μπερδεύεται με το δικό της', () async {
      final tasks = await repo.getFilteredTasks(
        const TaskFilter(statuses: [TaskStatus.open]),
      );
      final linked = tasks.firstWhere((t) => t.callId == callId);

      expect(linked.lansweeperMainTicketId, isNull);
      await TasksLansweeperRepository(
        db,
      ).markSubmitted(taskId: linked.id!, ticketId: '7100');

      final after = (await repo.getFilteredTasks(
        const TaskFilter(statuses: [TaskStatus.open]),
      )).firstWhere((t) => t.callId == callId);
      expect(after.lansweeperMainTicketId, '7100');
      expect(after.linkedCallTicketId, '6005');
    });
  });
}
