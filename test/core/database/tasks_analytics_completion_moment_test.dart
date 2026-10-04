// Τα Στατιστικά Εκκρεμοτήτων μετρούν τη στιγμή ΟΛΟΚΛΗΡΩΣΗΣ, όχι την ώρα της
// τελευταίας αλλαγής.
//
// Σενάριο: εκκρεμότητα που έκλεισε την 1η του μήνα και δέχτηκε μια διόρθωση
// κειμένου την 7η. Μετριέται στην 1η — αλλιώς ο μέσος χρόνος επίλυσης φουσκώνει
// κατά έξι μέρες και η καμπύλη δείχνει τη δουλειά σε λάθος ημέρα.
//
//   flutter test test/core/database/tasks_analytics_completion_moment_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Ημερομηνίες σε σταθερό, περασμένο μήνα: το τεστ δεν επιτρέπεται να αλλάζει
/// συμπεριφορά ανάλογα με το πότε τρέχει.
final DateTime _created = DateTime(2026, 3, 1, 9);
final DateTime _completed = DateTime(2026, 3, 1, 17);
final DateTime _editedLater = DateTime(2026, 3, 7, 11);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TasksRepository repo;
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('tasks_completion_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/tasks.db');
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

  /// Κλειστή εκκρεμότητα με ξεχωριστή στιγμή ολοκλήρωσης και τελευταίας αλλαγής.
  Future<void> insertClosedTask({
    required DateTime createdAt,
    required DateTime completedAt,
    required DateTime updatedAt,
  }) async {
    await db.insert('tasks', {
      'title': 'Δοκιμαστική εκκρεμότητα',
      'status': 'closed',
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': 0,
    });
  }

  /// Το διάστημα που περιέχει την ΟΛΟΚΛΗΡΩΣΗ αλλά όχι τη μεταγενέστερη διόρθωση.
  final rangeOfCompletionOnly = DateTimeRange(
    start: DateTime(2026, 3, 1),
    end: DateTime(2026, 3, 3),
  );

  /// Το διάστημα που περιέχει μόνο τη μεταγενέστερη διόρθωση.
  final rangeOfEditOnly = DateTimeRange(
    start: DateTime(2026, 3, 6),
    end: DateTime(2026, 3, 8),
  );

  group('πλήθος ολοκληρώσεων ανά διάστημα', () {
    test('μετριέται στο διάστημα της ολοκλήρωσης', () async {
      await insertClosedTask(
        createdAt: _created,
        completedAt: _completed,
        updatedAt: _editedLater,
      );

      final summary = await repo.getTaskAnalytics(rangeOfCompletionOnly);

      expect(
        summary.closedInRangeCount,
        1,
        reason:
            'Η εκκρεμότητα ολοκληρώθηκε 1/3 — πρέπει να μετριέται εκεί, όσες '
            'διορθώσεις κειμένου κι αν δεχτεί αργότερα.',
      );
    });

    test('ΔΕΝ μετριέται στο διάστημα της μεταγενέστερης διόρθωσης', () async {
      await insertClosedTask(
        createdAt: _created,
        completedAt: _completed,
        updatedAt: _editedLater,
      );

      final summary = await repo.getTaskAnalytics(rangeOfEditOnly);

      expect(
        summary.closedInRangeCount,
        0,
        reason:
            'Στις 7/3 δεν ολοκληρώθηκε τίποτα — μόνο διορθώθηκε ένα κείμενο.',
      );
    });
  });

  group('μέσος χρόνος επίλυσης', () {
    test(
      'μετρά ως τη στιγμή ολοκλήρωσης, όχι ως την τελευταία αλλαγή',
      () async {
        await insertClosedTask(
          createdAt: _created,
          completedAt: _completed,
          updatedAt: _editedLater,
        );

        final summary = await repo.getTaskAnalytics(rangeOfCompletionOnly);

        // 09:00 → 17:00 της ίδιας μέρας = 8 ώρες. Με το updated_at θα έβγαινε
        // πάνω από έξι μέρες.
        expect(
          summary.avgCompletionSeconds,
          closeTo(8 * 3600, 1),
          reason:
              'Ο μέσος χρόνος επίλυσης δεν επιτρέπεται να φουσκώνει από μια '
              'διόρθωση ορθογραφικού έξι μέρες αργότερα.',
        );
      },
    );
  });

  group('καμπύλη ολοκληρώσεων ανά ημέρα', () {
    test('η ολοκλήρωση προσμετράται στη μέρα που έγινε', () async {
      await insertClosedTask(
        createdAt: _created,
        completedAt: _completed,
        updatedAt: _editedLater,
      );

      // Τα sparklines καλύπτουν σκόπιμα τις ΤΕΛΕΥΤΑΙΕΣ 7 ημέρες του διαστήματος
      // (μικρογραφία τάσης, όχι ολόκληρο το εύρος). Το διάστημα 1/3–7/3 τα
      // κάνει να ξεκινούν ακριβώς στη μέρα της ολοκλήρωσης.
      final summary = await repo.getTaskAnalytics(
        DateTimeRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 7)),
      );

      // Η καμπύλη backlog κινείται μόνο όταν κλείνει κάτι: την 1/3 πρέπει να
      // έχει ήδη απορροφήσει το κλείσιμο.
      final firstDay = summary.backlogGrowth.first;
      final lastDay = summary.backlogGrowth.last;
      expect(
        firstDay.delta,
        lessThanOrEqualTo(0),
        reason: 'Την 1/3 έκλεισε μία εκκρεμότητα — το ισοζύγιο δεν ανεβαίνει.',
      );
      expect(
        lastDay.delta,
        0,
        reason: 'Στις 7/3 δεν δημιουργήθηκε ούτε έκλεισε τίποτα.',
      );

      final closedOnFirstDay = summary.sparklineClosed.first;
      final closedOnLastDay = summary.sparklineClosed.last;
      expect(closedOnFirstDay, 1, reason: 'μία ολοκλήρωση την 1/3');
      expect(closedOnLastDay, 0, reason: 'καμία ολοκλήρωση στις 7/3');
    });
  });

  group('παλιές εγγραφές χωρίς σφραγίδα', () {
    test(
      'εγγραφή χωρίς completed_at μετριέται από την τελευταία αλλαγή',
      () async {
        // Η μετάπτωση v40 γέμισε τις υπάρχουσες, αλλά μια βάση που δεν πέρασε
        // ποτέ από εκεί δεν επιτρέπεται να χάσει τις ολοκληρώσεις της.
        await db.insert('tasks', {
          'title': 'Παλιά κλειστή χωρίς σφραγίδα',
          'status': 'closed',
          'created_at': _created.toIso8601String(),
          'completed_at': null,
          'updated_at': _completed.toIso8601String(),
          'is_deleted': 0,
        });

        final summary = await repo.getTaskAnalytics(rangeOfCompletionOnly);

        expect(
          summary.closedInRangeCount,
          1,
          reason:
              'Χωρίς σφραγίδα, η ώρα τελευταίας αλλαγής είναι η καλύτερη γνωστή '
              'προσέγγιση — δεν εξαφανίζουμε την εγγραφή.',
        );
      },
    );
  });

  group('καμπύλη καθυστερημένων ανά ημέρα', () {
    Future<void> insertTask({
      required String status,
      required DateTime createdAt,
      DateTime? dueDate,
      bool deleted = false,
    }) async {
      await db.insert('tasks', {
        'title': 'Εκκρεμότητα $status',
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'updated_at': createdAt.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'is_deleted': deleted ? 1 : 0,
      });
    }

    // Κάθε μέρα μετρά όσες είναι ΣΗΜΕΡΑ ανοιχτές ή σε αναβολή, είχαν ήδη
    // δημιουργηθεί και η προθεσμία τους είχε περάσει ως το τέλος της μέρας.
    test('ΦΩΤΟΓΡΑΦΙΑ — οι μετρήσεις της εβδομάδας', () async {
      // Καθυστερημένη πριν ξεκινήσει η εβδομάδα: μετρά όλες τις μέρες.
      await insertTask(
        status: 'open',
        createdAt: DateTime(2026, 2, 20, 9),
        dueDate: DateTime(2026, 2, 25, 12),
      );
      // Σε αναβολή, η προθεσμία περνά στις 3/3.
      await insertTask(
        status: 'snoozed',
        createdAt: DateTime(2026, 3, 1, 8),
        dueDate: DateTime(2026, 3, 3, 10),
      );
      // Η προθεσμία είναι πριν τη δημιουργία: μετρά από τη μέρα δημιουργίας.
      await insertTask(
        status: 'open',
        createdAt: DateTime(2026, 3, 5, 9),
        dueDate: DateTime(2026, 3, 4, 9),
      );
      // Προθεσμία ακριβώς στα μεσάνυχτα της 6/3: δεν μετρά στις 5/3.
      await insertTask(
        status: 'open',
        createdAt: DateTime(2026, 3, 1),
        dueDate: DateTime(2026, 3, 6),
      );
      // Δεν μετρούν ποτέ: κλειστή, διαγραμμένη, χωρίς προθεσμία, μελλοντική.
      await insertTask(
        status: 'closed',
        createdAt: DateTime(2026, 2, 20),
        dueDate: DateTime(2026, 2, 25),
      );
      await insertTask(
        status: 'open',
        createdAt: DateTime(2026, 2, 20),
        dueDate: DateTime(2026, 2, 25),
        deleted: true,
      );
      await insertTask(status: 'open', createdAt: DateTime(2026, 2, 20));
      await insertTask(
        status: 'open',
        createdAt: DateTime(2026, 3, 1),
        dueDate: DateTime(2026, 3, 10),
      );

      final summary = await repo.getTaskAnalytics(
        DateTimeRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 7)),
      );

      expect(summary.sparklineOverdue, [1, 1, 2, 2, 3, 4, 4]);
    });

    // Προθεσμία 2/3, ολοκλήρωση 5/3 το μεσημέρι: καθυστερημένη 2/3–4/3 και
    // μέρος της 5/3· στο τέλος της 5/3 έχει πια κλείσει.
    test('όποια έκλεισε αργότερα μετρά τις μέρες που ήταν ανοιχτή', () async {
      await db.insert('tasks', {
        'title': 'Έκλεισε με καθυστέρηση',
        'status': 'closed',
        'created_at': DateTime(2026, 2, 27).toIso8601String(),
        'due_date': DateTime(2026, 3, 2, 10).toIso8601String(),
        'completed_at': DateTime(2026, 3, 5, 12).toIso8601String(),
        'updated_at': DateTime(2026, 3, 5, 12).toIso8601String(),
        'is_deleted': 0,
      });

      final summary = await repo.getTaskAnalytics(
        DateTimeRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 7)),
      );

      expect(summary.sparklineOverdue, [0, 1, 1, 1, 0, 0, 0]);
    });

    test('όποια διαγράφηκε αργότερα μετρά ως τη διαγραφή', () async {
      final id = await db.insert('tasks', {
        'title': 'Ακυρώθηκε με καθυστέρηση',
        'status': 'open',
        'created_at': DateTime(2026, 2, 27).toIso8601String(),
        'updated_at': DateTime(2026, 2, 27).toIso8601String(),
        'due_date': DateTime(2026, 3, 2, 10).toIso8601String(),
        'is_deleted': 1,
      });
      await db.insert('audit_log', {
        'entity_type': AuditEntityTypes.task,
        'entity_id': id,
        'action': DatabaseHelper.auditActionDelete,
        'timestamp': DateTime(2026, 3, 4, 9).toIso8601String(),
      });

      final summary = await repo.getTaskAnalytics(
        DateTimeRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 7)),
      );

      expect(summary.sparklineOverdue, [0, 1, 1, 0, 0, 0, 0]);
    });
  });

  group('ποσοστά ολοκλήρωσης και ακύρωσης', () {
    final week = DateTimeRange(
      start: DateTime(2026, 3, 1),
      end: DateTime(2026, 3, 7),
    );

    Future<int> insert({
      required String status,
      required DateTime createdAt,
      DateTime? completedAt,
      bool deleted = false,
    }) => db.insert('tasks', {
      'title': 'Εκκρεμότητα',
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': (completedAt ?? createdAt).toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'is_deleted': deleted ? 1 : 0,
    });

    // Άνοιξαν τρεις μέσα στην εβδομάδα: μία έκλεισε, μία ακυρώθηκε, μία
    // εκκρεμεί. Έκλεισαν και δύο παλιότερες — δεν ανήκουν στις τρεις.
    test(
      'μετρούν από όσες άνοιξαν στο διάστημα — ποτέ πάνω από 100%',
      () async {
        await insert(
          status: 'closed',
          createdAt: DateTime(2026, 3, 2, 9),
          completedAt: DateTime(2026, 3, 3, 9),
        );
        await insert(status: 'open', createdAt: DateTime(2026, 3, 2, 10));
        final cancelledId = await insert(
          status: 'open',
          createdAt: DateTime(2026, 3, 2, 11),
          deleted: true,
        );
        await db.insert('audit_log', {
          'entity_type': AuditEntityTypes.task,
          'entity_id': cancelledId,
          'action': DatabaseHelper.auditActionDelete,
          'timestamp': DateTime(2026, 3, 4, 9).toIso8601String(),
        });
        for (final day in [3, 4]) {
          await insert(
            status: 'closed',
            createdAt: DateTime(2026, 2, 20),
            completedAt: DateTime(2026, 3, day, 12),
          );
        }

        final summary = await repo.getTaskAnalytics(week);

        expect(
          summary.closedInRangeCount,
          3,
          reason: 'το μεγάλο νούμερο μένει',
        );
        expect(summary.completionRateInRange, closeTo(100 / 3, 0.01));
        expect(summary.cancellationRateInRange, closeTo(100 / 3, 0.01));
      },
    );
  });

  group('καμπύλη αναβολών ανά ημέρα', () {
    // Δύο αναβολές στις 2/3, μία στις 5/3· μία στις 25/2 είναι έξω από την
    // εβδομάδα, και η αναβολή διαγραμμένης εκκρεμότητας δεν μετρά.
    test('μετρά τις αναβολές της κάθε μέρας', () async {
      String history(List<DateTime> moments) => jsonEncode([
        for (final m in moments)
          {'snoozedAt': m.toIso8601String(), 'dueAt': m.toIso8601String()},
      ]);
      Future<void> insert(List<DateTime> snoozes, {bool deleted = false}) =>
          db.insert('tasks', {
            'title': 'Με αναβολές',
            'status': 'snoozed',
            'created_at': DateTime(2026, 2, 20).toIso8601String(),
            'updated_at': DateTime(2026, 2, 20).toIso8601String(),
            'snooze_history_json': history(snoozes),
            'is_deleted': deleted ? 1 : 0,
          });

      await insert([DateTime(2026, 2, 25, 9), DateTime(2026, 3, 2, 9)]);
      await insert([DateTime(2026, 3, 2, 15), DateTime(2026, 3, 5, 10)]);
      await insert([DateTime(2026, 3, 4, 10)], deleted: true);

      final summary = await repo.getTaskAnalytics(
        DateTimeRange(start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 7)),
      );

      expect(summary.sparklineSnoozes, [0, 2, 0, 0, 1, 0, 0]);
    });
  });
}
