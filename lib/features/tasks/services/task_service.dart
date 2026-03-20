import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/database_helper.dart';
import '../models/task.dart';
import '../models/task_filter.dart';
import '../models/task_snooze_config.dart';

/// Κλήση με status pending που δεν έχει αντίστοιχο task.
class OrphanCall {
  const OrphanCall({
    required this.id,
    this.date,
    this.time,
    this.callerId,
    this.callerText,
    this.issue,
  });

  final int id;
  final String? date;
  final String? time;
  final int? callerId;
  final String? callerText;
  final String? issue;
}

/// Υπηρεσία ανάγνωσης εργασιών από τον πίνακα tasks.
class TaskService {
  Future<Database> get _db => DatabaseHelper.instance.database;
  bool? _hasSnoozeHistoryColumnCache;

  Future<bool> _hasSnoozeHistoryColumn(Database db) async {
    final cached = _hasSnoozeHistoryColumnCache;
    if (cached != null) return cached;
    final info = await db.rawQuery('PRAGMA table_info(tasks)');
    final has = info.any((row) => row['name'] == 'snooze_history_json');
    _hasSnoozeHistoryColumnCache = has;
    return has;
  }

  /// Ρυθμίσεις αναβολών / εργάσιμων ωρών από `app_settings` (JSON).
  Future<TaskSnoozeConfig> getSnoozeConfig() async {
    final raw =
        await DatabaseHelper.instance.getSetting(TaskSnoozeConfig.appSettingsKey);
    if (raw == null || raw.trim().isEmpty) {
      return TaskSnoozeConfig.defaultConfig();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TaskSnoozeConfig.fromMap(decoded);
      }
      if (decoded is Map) {
        return TaskSnoozeConfig.fromMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return TaskSnoozeConfig.defaultConfig();
  }

  /// Συμβατότητα: ίδιο με [getSnoozeConfig].
  Future<TaskSnoozeConfig> getTaskSnoozeConfig() => getSnoozeConfig();

  /// Επόμενη προτεινόμενη ημερομηνία/ώρα λήξης βάσει ρυθμίσεων.
  ///
  /// [option]: `TaskSnoozeConfig.kOptionDefault` → χρήση [TaskSnoozeConfig.defaultSnoozeOption],
  /// αλλιώς `one_hour` / `day_end` / `next_business`.
  DateTime calculateNextDueDate(
    TaskSnoozeConfig config, {
    String option = TaskSnoozeConfig.kOptionDefault,
    DateTime? fromDate,
  }) {
    final base = fromDate ?? DateTime.now();
    final resolved = (option == TaskSnoozeConfig.kOptionDefault || option.isEmpty)
        ? config.defaultSnoozeOption
        : TaskSnoozeConfig.normalizeSnoozeOption(option);

    switch (resolved) {
      case TaskSnoozeConfig.kOneHour:
        return base.add(const Duration(hours: 1));
      case TaskSnoozeConfig.kDayEnd:
        return _nextDayEndDateTime(config, base);
      case TaskSnoozeConfig.kNextBusiness:
        return _nextBusinessMorningDateTime(config, base);
      default:
        return base.add(const Duration(hours: 1));
    }
  }

  DateTime _atTimeOnDay(DateTime dayStart, TimeOfDay t) {
    return DateTime(dayStart.year, dayStart.month, dayStart.day, t.hour, t.minute);
  }

  /// Τέλος «μέσα στην ημέρα»: σήμερα στο [dayEndTime] αν ακόμα μετά το [base], αλλιώς επόμενες ημέρες (+ Σ/Κ αν [skipWeekends]).
  DateTime _nextDayEndDateTime(TaskSnoozeConfig config, DateTime base) {
    var day = DateTime(base.year, base.month, base.day);
    var candidate = _atTimeOnDay(day, config.dayEndTime);
    if (!candidate.isAfter(base)) {
      day = day.add(const Duration(days: 1));
      candidate = _atTimeOnDay(day, config.dayEndTime);
    }
    if (config.skipWeekends) {
      while (candidate.weekday == DateTime.saturday ||
          candidate.weekday == DateTime.sunday) {
        day = day.add(const Duration(days: 1));
        candidate = _atTimeOnDay(day, config.dayEndTime);
      }
    }
    return candidate;
  }

  /// Επόμενη ημέρα (ημερολογιακά μετά την ημέρα του [base]) στην [nextBusinessHour], με παράλειψη Σ/Κ αν [skipWeekends].
  DateTime _nextBusinessMorningDateTime(TaskSnoozeConfig config, DateTime base) {
    var day = DateTime(base.year, base.month, base.day);
    day = day.add(const Duration(days: 1));
    var candidate = _atTimeOnDay(day, config.nextBusinessHour);
    if (config.skipWeekends) {
      while (candidate.weekday == DateTime.saturday ||
          candidate.weekday == DateTime.sunday) {
        day = day.add(const Duration(days: 1));
        candidate = _atTimeOnDay(day, config.nextBusinessHour);
      }
    }
    return candidate;
  }

  /// Αποθήκευση ρυθμίσεων αναβολών στο `app_settings`.
  Future<void> saveTaskSnoozeConfig(TaskSnoozeConfig config) async {
    await DatabaseHelper.instance.setSetting(
      TaskSnoozeConfig.appSettingsKey,
      jsonEncode(config.toMap()),
    );
  }

  /// Δημιουργεί εκκρεμότητα από κλήση ή αυτόνομα ([callId] null = χωρίς εγγραφή κλήσης).
  Future<int> createFromCall({
    int? callId,
    required String? callerName,
    required String description,
    required DateTime callDate,
  }) async {
    final name = (callerName == null || callerName.trim().isEmpty)
        ? 'Άγνωστος καλών'
        : callerName.trim();
    final title =
        '$name – Εκκρεμότητα στις ${DateFormat('dd/MM/yyyy').format(callDate)}';
    final config = await getSnoozeConfig();
    final dueDate = calculateNextDueDate(
      config,
      option: TaskSnoozeConfig.kOptionDefault,
      fromDate: DateTime.now(),
    );
    final db = await _db;
    final row = <String, dynamic>{
      'call_id': callId,
      'title': title,
      'description': description,
      'due_date': dueDate.toIso8601String(),
      'status': 'open',
    };
    final id = await db.insert('tasks', row);
    return id;
  }

  Future<List<Task>> getOpenTasks() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT * FROM tasks WHERE status = 'open' ORDER BY due_date ASC",
    );
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  Future<List<Task>> getOverdueTasks() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT * FROM tasks WHERE status = 'open' AND due_date < datetime('now') ORDER BY due_date ASC",
    );
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  Future<List<Task>> getUpcomingTasks({int limit = 50}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT * FROM tasks WHERE status = 'open' AND due_date >= datetime('now') ORDER BY due_date ASC LIMIT $limit",
    );
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  /// Λίστα tasks με δυναμικό φίλτρο (search, statuses, ημερομηνίες). Ταξινόμηση due_date ASC.
  Future<List<Task>> getFilteredTasks(TaskFilter filter) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];

    if (filter.searchQuery.trim().isNotEmpty) {
      final pattern = '%${filter.searchQuery.trim()}%';
      conditions.add('(title LIKE ? OR description LIKE ?)');
      args.add(pattern);
      args.add(pattern);
    }
    if (filter.statuses.isNotEmpty) {
      final placeholders = List.filled(filter.statuses.length, '?').join(',');
      conditions.add('status IN ($placeholders)');
      for (final s in filter.statuses) {
        args.add(s.toDbValue);
      }
    }
    if (filter.startDate != null) {
      conditions.add('due_date >= ?');
      args.add(filter.startDate!.toIso8601String());
    }
    if (filter.endDate != null) {
      conditions.add('due_date <= ?');
      args.add(filter.endDate!.toIso8601String());
    }

    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await db.rawQuery(
      'SELECT * FROM tasks $where ORDER BY due_date ASC',
      args,
    );
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  /// Δημιουργεί νέα εγγραφή στον πίνακα tasks. Επιστρέφει το νέο id.
  Future<int> createTask(Task task) async {
    final db = await _db;
    final map = task.toMap();
    map.remove('id');
    if (!await _hasSnoozeHistoryColumn(db)) {
      map.remove('snooze_history_json');
    }
    final now = DateTime.now().toIso8601String();
    map['created_at'] = now;
    map['updated_at'] = now;
    return db.insert('tasks', map);
  }

  /// Ενημερώνει μια υπάρχουσα εγγραφή στον πίνακα tasks.
  Future<void> updateTask(Task task) async {
    if (task.id == null) return;
    final db = await _db;
    final map = task.toMap();
    map.remove('id');
    if (!await _hasSnoozeHistoryColumn(db)) {
      map.remove('snooze_history_json');
    }
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update(
      'tasks',
      map,
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  /// Διαγράφει την εγγραφή βάσει ID.
  Future<void> deleteTask(int id) async {
    final db = await _db;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  /// Ορίζει status = closed, solution_notes και updated_at.
  Future<void> closeTask(int id, String solutionNotes) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'tasks',
      {
        'status': 'closed',
        'solution_notes': solutionNotes,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Κλήσεις με status pending που δεν έχουν αντίστοιχο task.
  Future<List<OrphanCall>> getCallsWithoutTask() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT c.id, c.date, c.time, c.caller_id, c.caller_text, c.issue
      FROM calls c
      LEFT JOIN tasks t ON t.call_id = c.id
      WHERE t.id IS NULL AND c.status = 'pending'
      ORDER BY c.id
    ''');
    return rows
        .map((r) => OrphanCall(
              id: r['id'] as int,
              date: r['date'] as String?,
              time: r['time'] as String?,
              callerId: r['caller_id'] as int?,
              callerText: r['caller_text'] as String?,
              issue: r['issue'] as String?,
            ))
        .toList();
  }

  /// Δημιουργεί task για κάθε κλήση χωρίς εκκρεμότητα. Επιστρέφει πλήθος δημιουργημένων.
  Future<int> createTasksForOrphanCalls() async {
    final orphans = await getCallsWithoutTask();
    if (orphans.isEmpty) return 0;
    final db = await _db;
    int created = 0;
    for (final o in orphans) {
      String? callerName;
      if (o.callerId != null) {
        final userRows = await db.query(
          'users',
          columns: ['first_name', 'last_name'],
          where: 'id = ?',
          whereArgs: [o.callerId],
        );
        if (userRows.isNotEmpty) {
          final f = userRows.first['first_name'] as String? ?? '';
          final l = userRows.first['last_name'] as String? ?? '';
          callerName = '$f $l'.trim();
        }
      }
      if (callerName == null || callerName.isEmpty) {
        callerName = o.callerText?.trim().isEmpty == true ? null : o.callerText?.trim();
      }
      DateTime callDate = DateTime.now();
      if (o.date != null && o.date!.isNotEmpty) {
        final datePart = o.date!;
        final timePart = o.time ?? '00:00';
        final parsed = DateTime.tryParse('$datePart $timePart');
        if (parsed != null) callDate = parsed;
      }
      await createFromCall(
        callId: o.id,
        callerName: callerName,
        description: o.issue ?? '',
        callDate: callDate,
      );
      created++;
    }
    return created;
  }
}
