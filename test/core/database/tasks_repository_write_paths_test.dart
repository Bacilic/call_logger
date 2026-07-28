// Χαρακτηρισμός των κρίσιμων διαδρομών εγγραφής του TasksRepository
// (δημιουργία, τροποποίηση, κλείσιμο, soft διαγραφή εκκρεμότητας):
// τι γράφεται στη βάση και τι ίχνος μένει στο audit_log.
//
//   flutter test test/core/database/tasks_repository_write_paths_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('TasksRepository — διαδρομές εγγραφής', () {
    late TasksRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'tasks_repository_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/tasks_repo.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('tasks');
      repo = TasksRepository();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Map<String, dynamic>? decodeJson(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    Task newTask({String title = 'Έλεγχος εκτυπωτή στη Γραμματεία'}) => Task(
      title: title,
      description: 'Ο εκτυπωτής βγάζει κενές σελίδες μετά το τελευταίο τόνερ.',
      dueDate: DateTime(2026, 8, 1, 9, 0).toIso8601String(),
      status: 'open',
    );

    test('createTask: γράφει χρονοσφραγίδες, search_index και audit', () async {
      final id = await repo.createTask(newTask());

      final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['created_at'], isNotNull);
      expect(row['updated_at'], row['created_at']);
      final searchIndex = (row['search_index'] as String?) ?? '';
      expect(
        searchIndex,
        isNotEmpty,
        reason: 'Χωρίς search_index η εκκρεμότητα δεν βρίσκεται στην αναζήτηση',
      );

      final audit = await db.query(
        'audit_log',
        where: 'action = ? AND entity_type = ? AND entity_id = ?',
        whereArgs: ['ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ', AuditEntityTypes.task, id],
      );
      expect(audit, hasLength(1));
      final nv = decodeJson(audit.single['new_values_json'] as String?);
      expect(nv?['title'], 'Έλεγχος εκτυπωτή στη Γραμματεία');
    });

    test('closeTask: κλείσιμο + λύση + audit με το παλιό status', () async {
      final id = await repo.createTask(newTask());

      await repo.closeTask(id, 'Αντικαταστάθηκε το τόνερ.');

      final row = (await db.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(row['status'], 'closed');
      expect(row['solution_notes'], 'Αντικαταστάθηκε το τόνερ.');

      final audit = await db.query(
        'audit_log',
        where: 'action = ? AND entity_id = ?',
        whereArgs: ['ΚΛΕΙΣΙΜΟ ΕΚΚΡΕΜΟΤΗΤΑΣ', id],
      );
      expect(audit, hasLength(1));
      expect(
        decodeJson(audit.single['old_values_json'] as String?)?['status'],
        'open',
      );
      expect(
        decodeJson(audit.single['new_values_json'] as String?)?['status'],
        'closed',
      );
    });

    test('closeTask σε ανύπαρκτο id: καμία εγγραφή, κανένα audit', () async {
      await repo.closeTask(987654, 'δεν υπάρχει');

      final audit = await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: ['ΚΛΕΙΣΙΜΟ ΕΚΚΡΕΜΟΤΗΤΑΣ'],
      );
      expect(audit, isEmpty);
    });

    test('updateTask: αλλαγή τίτλου αφήνει audit με το πριν/μετά', () async {
      final id = await repo.createTask(newTask());
      final stored = Task.fromMap(
        (await db.query('tasks', where: 'id = ?', whereArgs: [id])).single,
      );

      await repo.updateTask(
        stored.copyWith(title: 'Έλεγχος εκτυπωτή — 2ος όροφος'),
      );

      final row = (await db.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(row['title'], 'Έλεγχος εκτυπωτή — 2ος όροφος');

      final audit = await db.query(
        'audit_log',
        where: 'action = ? AND entity_id = ?',
        whereArgs: ['ΤΡΟΠΟΠΟΙΗΣΗ ΕΚΚΡΕΜΟΤΗΤΑΣ', id],
      );
      expect(audit, hasLength(1));
      expect(
        decodeJson(audit.single['old_values_json'] as String?)?['title'],
        'Έλεγχος εκτυπωτή στη Γραμματεία',
      );
    });

    test('updateTask χωρίς ουσιαστική αλλαγή: κανένα audit-θόρυβος', () async {
      final id = await repo.createTask(newTask());
      final stored = Task.fromMap(
        (await db.query('tasks', where: 'id = ?', whereArgs: [id])).single,
      );
      await db.delete('audit_log');

      await repo.updateTask(stored);

      final audit = await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: ['ΤΡΟΠΟΠΟΙΗΣΗ ΕΚΚΡΕΜΟΤΗΤΑΣ'],
      );
      expect(
        audit,
        isEmpty,
        reason:
            'Αποθήκευση χωρίς αλλαγή στα ελεγχόμενα πεδία δεν πρέπει να '
            'γεμίζει το ιστορικό με κενές τροποποιήσεις',
      );
    });

    test(
      'deleteTask: soft διαγραφή — η γραμμή μένει με is_deleted=1',
      () async {
        final id = await repo.createTask(newTask());

        await repo.deleteTask(id);

        final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
        expect(
          rows,
          hasLength(1),
          reason: 'Soft delete: η εγγραφή διατηρείται',
        );
        expect(rows.single['is_deleted'], 1);
      },
    );
  });
}
