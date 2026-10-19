// Η αναφορά εκκρεμοτήτων: οι «ακυρωμένες» μετρούν εκκρεμότητες, όχι εγγραφές
// διαγραφής στο Ιστορικό.
//
//   flutter test test/core/database/tasks_analytics_repository_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_analytics_repository.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('tasks_analytics_test_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/analytics.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('tasks');
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  test('εκκρεμότητα με δύο εγγραφές διαγραφής μετρά μία ακύρωση', () async {
    final repo = TasksRepository();
    final id = await repo.createTask(
      Task(
        title: 'Εκτυπωτής Γραμματείας ΤΕΠ',
        dueDate: DateTime.now().toIso8601String(),
        status: 'open',
      ),
    );
    await repo.deleteTask(id);
    await repo.deleteTask(id);

    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final summary = await TasksAnalyticsRepository(
      db,
    ).getTaskAnalytics(DateTimeRange(start: day, end: day));

    expect(summary.cancelledInRangeCount, 1);
    expect(summary.sparklineCancelled.fold<double>(0, (a, b) => a + b), 1);
  });
}
