import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/utils/search_text_normalizer.dart';
import '../models/task.dart';
import '../models/task_filter.dart' show TaskFilter, TaskSortOption;
import '../models/task_settings_config.dart';

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

  /// Γενικές ρυθμίσεις εκκρεμοτήτων από `app_settings` (JSON).
  ///
  /// - Διαβάζει πρώτα από [TaskSettingsConfig.appSettingsKey].
  /// - Αν λείπει, κάνει fallback στο [TaskSettingsConfig.legacyAppSettingsKey].
  Future<TaskSettingsConfig> getTaskSettingsConfig() async {
    final db = DatabaseHelper.instance;
    final raw =
        await db.getSetting(TaskSettingsConfig.appSettingsKey) ??
        await db.getSetting(TaskSettingsConfig.legacyAppSettingsKey);
    if (raw == null || raw.trim().isEmpty) {
      return TaskSettingsConfig.defaultConfig();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TaskSettingsConfig.fromMap(decoded);
      }
      if (decoded is Map) {
        return TaskSettingsConfig.fromMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return TaskSettingsConfig.defaultConfig();
  }

  /// Επόμενη προτεινόμενη ημερομηνία/ώρα λήξης βάσει ρυθμίσεων.
  ///
  /// [option]: `TaskSettingsConfig.kOptionDefault` → χρήση [TaskSettingsConfig.defaultSnoozeOption],
  /// αλλιώς `one_hour` / `day_end` / `next_business`.
  DateTime calculateNextDueDate(
    TaskSettingsConfig config, {
    String option = TaskSettingsConfig.kOptionDefault,
    DateTime? fromDate,
  }) {
    final base = fromDate ?? DateTime.now();
    final resolved =
        (option == TaskSettingsConfig.kOptionDefault || option.isEmpty)
        ? config.defaultSnoozeOption
        : TaskSettingsConfig.normalizeSnoozeOption(option);

    switch (resolved) {
      case TaskSettingsConfig.kOneHour:
        return base.add(const Duration(hours: 1));
      case TaskSettingsConfig.kDayEnd:
        return _nextDayEndDateTime(config, base);
      case TaskSettingsConfig.kNextBusiness:
        return _nextBusinessMorningDateTime(config, base);
      default:
        return base.add(const Duration(hours: 1));
    }
  }

  DateTime _atTimeOnDay(DateTime dayStart, TimeOfDay t) {
    return DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      t.hour,
      t.minute,
    );
  }

  /// Τέλος «μέσα στην ημέρα»: σήμερα στο [dayEndTime] αν ακόμα μετά το [base], αλλιώς επόμενες ημέρες (+ Σ/Κ αν [skipWeekends]).
  DateTime _nextDayEndDateTime(TaskSettingsConfig config, DateTime base) {
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
  DateTime _nextBusinessMorningDateTime(
    TaskSettingsConfig config,
    DateTime base,
  ) {
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

  /// Αποθήκευση ρυθμίσεων εκκρεμοτήτων στο `app_settings`.
  Future<void> saveTaskSettingsConfig(TaskSettingsConfig config) async {
    await DatabaseHelper.instance.setSetting(
      TaskSettingsConfig.appSettingsKey,
      jsonEncode(config.toMap()),
    );
  }

  /// Τίτλος εκκρεμότητας από σημειώσεις/κατηγορία (μορφή φόρμας κλήσης).
  /// Ο εξοπλισμός περνά μόνο ως metadata (`equipment_text` / FK), όχι στον τίτλο.
  ///
  /// `description` = πλήρες κείμενο σημειώσεων (το ίδιο αποθηκεύεται στο task.description).
  static String smartTaskTitleFromCallContext({
    required String description,
    String? categoryName,
    required DateTime titleAt,
    String? callerFallback,
  }) {
    final notesRaw = description.contains(Task.quickAddTag)
        ? description.replaceAll(Task.quickAddTag, '').trim()
        : description;
    String snippet = '';
    if (notesRaw.isNotEmpty) {
      var line = notesRaw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      line = line.replaceAll(RegExp(r' +'), ' ');
      if (line.length > 40) {
        snippet = '${line.substring(0, 40)}...';
      } else {
        snippet = line;
      }
    }

    final categoryPart = (categoryName ?? '').trim();

    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(titleAt);
    final right = categoryPart.isNotEmpty
        ? '$categoryPart ($dateStr)'
        : '($dateStr)';

    if (snippet.isEmpty) {
      if (categoryPart.isEmpty &&
          callerFallback != null &&
          callerFallback.trim().isNotEmpty) {
        return '${callerFallback.trim()} | $right';
      }
      return right;
    }
    return '$snippet | $right';
  }

  /// Δημιουργεί εκκρεμότητα από κλήση ή αυτόνομα ([callId] null = χωρίς εγγραφή κλήσης).
  Future<int> createFromCall({
    int? callId,
    required String? callerName,
    required String description,
    required DateTime callDate,
    int? callerId,
    int? equipmentId,
    int? departmentId,
    int? phoneId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
    String? categoryName,
    DateTime? titleTimestamp,
    int? priority,
  }) async {
    final titleAt = titleTimestamp ?? callDate;
    final title = smartTaskTitleFromCallContext(
      description: description,
      categoryName: categoryName,
      titleAt: titleAt,
      callerFallback: callerName,
    );
    final config = await getTaskSettingsConfig();
    final dueDate = calculateNextDueDate(
      config,
      option: TaskSettingsConfig.kOptionDefault,
      fromDate: DateTime.now(),
    );
    final db = await _db;
    final row = <String, dynamic>{
      'call_id': callId,
      'title': title,
      'description': description,
      'due_date': dueDate.toIso8601String(),
      'status': 'open',
      'priority': priority,
      'caller_id': callerId,
      'equipment_id': equipmentId,
      'department_id': departmentId,
      'phone_id': phoneId,
      'phone_text': phoneText,
      'user_text': userText,
      'equipment_text': equipmentText,
      'department_text': departmentText,
      'is_deleted': 0,
      'search_index': SearchTextNormalizer.normalizeForSearch(
        [
          title,
          description,
          userText ?? '',
          phoneText ?? '',
          equipmentText ?? '',
          departmentText ?? '',
        ].join(' '),
      ),
    };
    final id = await db.insert('tasks', row);
    return id;
  }

  Future<List<Task>> getOpenTasks() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT * FROM tasks WHERE status = 'open' AND COALESCE(is_deleted, 0) = 0 ORDER BY due_date ASC",
    );
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  Future<List<Task>> getOverdueTasks() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT * FROM tasks WHERE status = 'open' AND due_date < datetime('now') AND COALESCE(is_deleted, 0) = 0 ORDER BY due_date ASC",
    );
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  Future<List<Task>> getUpcomingTasks({int limit = 50}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT * FROM tasks WHERE status = 'open' AND due_date >= datetime('now') AND COALESCE(is_deleted, 0) = 0 ORDER BY due_date ASC LIMIT $limit",
    );
    return rows.map((row) => Task.fromMap(row)).toList();
  }

  /// Συνολικό πλήθος εκκρεμοτήτων `open` + `snoozed` (για badge μενού).
  Future<int> getGlobalPendingTasksCount() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COUNT(id) AS count FROM tasks WHERE status IN ('open', 'snoozed') AND COALESCE(is_deleted, 0) = 0",
    );
    if (rows.isEmpty) return 0;
    final n = rows.first['count'];
    return n is int ? n : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
  }

  void _appendTaskFilterWhereParts(
    TaskFilter filter,
    List<String> conditions,
    List<Object?> args, {
    bool includeStatuses = true,
  }) {
    conditions.add('COALESCE(tasks.is_deleted, 0) = 0');
    if (filter.searchQuery.trim().isNotEmpty) {
      final normalizedQuery = SearchTextNormalizer.normalizeForSearch(
        filter.searchQuery,
      );
      final tokens = normalizedQuery
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
      for (final token in tokens) {
        conditions.add('search_index LIKE ?');
        args.add('%$token%');
      }
    }

    if (includeStatuses && filter.statuses.isNotEmpty) {
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
  }

  /// Πλήθος ανά `status` με ίδια φίλτρα αναζήτησης/ημερομηνίας με [getFilteredTasks],
  /// χωρίς φίλτρο επιλεγμένων statuses (για μετρητές στα chips).
  Future<Map<TaskStatus, int>> getTaskCounts(TaskFilter filter) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    _appendTaskFilterWhereParts(filter, conditions, args, includeStatuses: false);
    final where =
        conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final rows = await db.rawQuery(
      'SELECT tasks.status AS status, COUNT(DISTINCT tasks.id) AS count '
      'FROM tasks $where GROUP BY tasks.status',
      args,
    );

    final result = <TaskStatus, int>{
      for (final s in TaskStatus.values) s: 0,
    };
    for (final row in rows) {
      final raw = row['status'] as String?;
      if (raw == null) continue;
      final status = TaskStatusX.fromString(raw);
      final n = row['count'];
      final c = n is int ? n : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
      result[status] = c;
    }
    return result;
  }

  /// Λίστα tasks με δυναμικό φίλτρο (search, statuses, ημερομηνίες) και ταξινόμηση.
  Future<List<Task>> getFilteredTasks(TaskFilter filter) async {
    final db = await _db;
    final conditions = <String>[];
    final args = <Object?>[];
    _appendTaskFilterWhereParts(filter, conditions, args, includeStatuses: true);

    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    // Στήλη λήξης στο σχήμα: `due_date` (όχι due_at).
    final sortColumn = switch (filter.sortBy) {
      TaskSortOption.createdAt => 'created_at',
      TaskSortOption.dueAt => 'due_date',
      TaskSortOption.priority => 'priority',
      TaskSortOption.department => 'department_text',
      TaskSortOption.user => 'user_text',
      TaskSortOption.equipment => 'equipment_text',
    };
    final sortDirection = filter.sortAscending ? 'ASC' : 'DESC';
    final orderByClause = 'ORDER BY $sortColumn $sortDirection';

    final rows = await db.rawQuery(
      'SELECT * FROM tasks $where $orderByClause',
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
    map['search_index'] = SearchTextNormalizer.normalizeForSearch(
      task.combinedSearchText,
    );
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
    map['search_index'] = SearchTextNormalizer.normalizeForSearch(
      task.combinedSearchText,
    );
    await db.update('tasks', map, where: 'id = ?', whereArgs: [task.id]);
  }

  /// Soft delete εγγραφής βάσει ID (audit στο [DatabaseHelper]).
  Future<void> deleteTask(int id) async {
    await DatabaseHelper.instance.softDeleteTask(id);
  }

  /// Ορίζει status = closed, solution_notes και updated_at.
  Future<void> closeTask(int id, String solutionNotes) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'tasks',
      {'status': 'closed', 'solution_notes': solutionNotes, 'updated_at': now},
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
      LEFT JOIN tasks t ON t.call_id = c.id AND COALESCE(t.is_deleted, 0) = 0
      WHERE t.id IS NULL AND c.status = 'pending' AND COALESCE(c.is_deleted, 0) = 0
      ORDER BY c.id
    ''');
    return rows
        .map(
          (r) => OrphanCall(
            id: r['id'] as int,
            date: r['date'] as String?,
            time: r['time'] as String?,
            callerId: r['caller_id'] as int?,
            callerText: r['caller_text'] as String?,
            issue: r['issue'] as String?,
          ),
        )
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
        callerName = o.callerText?.trim().isEmpty == true
            ? null
            : o.callerText?.trim();
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
        titleTimestamp: callDate,
      );
      created++;
    }
    return created;
  }
}
