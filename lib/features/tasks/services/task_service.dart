import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/services/audit_service.dart';
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

  static const List<String> _kTaskAuditKeys = [
    'call_id',
    'caller_id',
    'equipment_id',
    'department_id',
    'phone_id',
    'phone_text',
    'user_text',
    'equipment_text',
    'department_text',
    'title',
    'description',
    'due_date',
    'snooze_until',
    'status',
    'priority',
    'solution_notes',
    'is_deleted',
  ];

  Future<void> _auditTaskCreate(Database db, int id, Map<String, dynamic> row) async {
    try {
      final user = await AuditService.performingUser(db);
      final nv = <String, dynamic>{};
      for (final k in _kTaskAuditKeys) {
        if (row.containsKey(k) && row[k] != null) nv[k] = row[k];
      }
      await AuditService.log(
        db,
        action: 'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ',
        userPerforming: user,
        details: 'tasks id=$id',
        entityType: AuditEntityTypes.task,
        entityId: id,
        entityName: row['title']?.toString(),
        newValues: nv.isEmpty ? null : nv,
      );
    } catch (_) {}
  }

  Future<void> _auditTaskUpdate(
    Database db,
    int id,
    Map<String, dynamic> oldRow,
    Map<String, dynamic> newMap,
  ) async {
    try {
      final oldDiff = <String, dynamic>{};
      final newDiff = <String, dynamic>{};
      for (final k in _kTaskAuditKeys) {
        final a = oldRow[k];
        final b = newMap[k];
        if ('${a ?? ''}' != '${b ?? ''}') {
          oldDiff[k] = a;
          newDiff[k] = b;
        }
      }
      if (newDiff.isEmpty) return;
      final user = await AuditService.performingUser(db);
      await AuditService.log(
        db,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΕΚΚΡΕΜΟΤΗΤΑΣ',
        userPerforming: user,
        details: 'tasks id=$id',
        entityType: AuditEntityTypes.task,
        entityId: id,
        entityName: newMap['title']?.toString() ?? oldRow['title']?.toString(),
        oldValues: oldDiff,
        newValues: newDiff,
      );
    } catch (_) {}
  }

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
    final dbConn = await DatabaseHelper.instance.database;
    final dir = DirectoryRepository(dbConn);
    final raw =
        await dir.getSetting(TaskSettingsConfig.appSettingsKey) ??
        await dir.getSetting(TaskSettingsConfig.legacyAppSettingsKey);
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
  /// αλλιώς `one_hour` / `day_end` («Μέσα στο ωράριο») / `next_business`.
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

    return switch (resolved) {
      TaskSettingsConfig.kOneHour => base.add(const Duration(hours: 1)),
      TaskSettingsConfig.kDayEnd =>
        _withinScheduleOrNextBusinessDue(config, base),
      TaskSettingsConfig.kNextBusiness =>
        _nextBusinessMorningDateTime(config, base),
      _ => base.add(const Duration(hours: 1)),
    };
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

  /// Επιλογή «Μέσα στο ωράριο» (`kDayEnd`): αν η [base] την ίδια ημερολογιακή ημέρα
  /// βρίσκεται από [nextBusinessHour] έως [dayEndTime] (συμπεριλαμβανομένων), +1 ώρα·
  /// αλλιώς επόμενη εργάσιμη στην [nextBusinessHour]. Αν το ωράριο δεν είναι έγκυρο
  /// (λήξη πριν την έναρξη), εφαρμόζεται +1 ώρα.
  DateTime _withinScheduleOrNextBusinessDue(
    TaskSettingsConfig config,
    DateTime base,
  ) {
    final dayStart = DateTime(base.year, base.month, base.day);
    final startToday = _atTimeOnDay(dayStart, config.nextBusinessHour);
    final endToday = _atTimeOnDay(dayStart, config.dayEndTime);
    if (!endToday.isAfter(startToday)) {
      return base.add(const Duration(hours: 1));
    }
    if (!base.isBefore(startToday) && !base.isAfter(endToday)) {
      return base.add(const Duration(hours: 1));
    }
    return _nextBusinessMorningDateTime(config, base);
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
    final dbSave = await DatabaseHelper.instance.database;
    await DirectoryRepository(dbSave).setSetting(
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
    final nowIso = DateTime.now().toIso8601String();
    final row = <String, dynamic>{
      'call_id': callId,
      'created_at': nowIso,
      'updated_at': nowIso,
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
    await _auditTaskCreate(db, id, row);
    return id;
  }

  /// Προσθέτει γραμμή στην περιγραφή ανοιχτής γρήγορης εκκρεμότητας (ίδιο [taskId]).
  /// Επιστρέφει false αν λείπει η εγγραφή, είναι διαγραμμένη/κλειστή ή δεν είναι quick-add.
  Future<bool> appendToQuickAddDescription(int taskId, String addition) async {
    final a = addition.trim();
    if (a.isEmpty) return false;
    final db = await _db;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final task = Task.fromMap(rows.first);
    if (task.isDeleted || !task.isQuickAdd) return false;
    if (task.status == TaskStatus.closed.toDbValue) return false;
    final desc = (task.description ?? '').trim();
    final newDesc = desc.isEmpty ? '${Task.quickAddTag} $a' : '$desc\n$a';
    await updateTask(task.copyWith(description: newDesc));
    return true;
  }

  /// Συμπληρώνει κενά FK/snapshot πεδία σε γρήγορη εκκρεμότητα (χωρίς αντικατάσταση μη κενών).
  Future<bool> mergeQuickAddEntitySnapshot({
    required int taskId,
    int? callerId,
    int? departmentId,
    int? equipmentId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    var task = Task.fromMap(rows.first);
    if (task.isDeleted || !task.isQuickAdd) return false;

    var next = task;
    var changed = false;

    if (task.callerId == null && callerId != null) {
      next = next.copyWith(callerId: callerId);
      changed = true;
    }
    if (task.departmentId == null && departmentId != null) {
      next = next.copyWith(departmentId: departmentId);
      changed = true;
    }
    if (task.equipmentId == null && equipmentId != null) {
      next = next.copyWith(equipmentId: equipmentId);
      changed = true;
    }

    String? pickText(String? current, String? incoming) {
      final inc = incoming?.trim();
      if (inc == null || inc.isEmpty) return null;
      final cur = current?.trim() ?? '';
      if (cur.isEmpty) return inc;
      return null;
    }

    final u = pickText(next.userText, userText);
    if (u != null) {
      next = next.copyWith(userText: u);
      changed = true;
    }
    final p = pickText(next.phoneText, phoneText);
    if (p != null) {
      next = next.copyWith(phoneText: p);
      changed = true;
    }
    final e = pickText(next.equipmentText, equipmentText);
    if (e != null) {
      next = next.copyWith(equipmentText: e);
      changed = true;
    }
    final d = pickText(next.departmentText, departmentText);
    if (d != null) {
      next = next.copyWith(departmentText: d);
      changed = true;
    }

    if (!changed) return false;
    await updateTask(next);
    return true;
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
      final c =
          n is int ? n : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
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
    final id = await db.insert('tasks', map);
    await _auditTaskCreate(db, id, map);
    return id;
  }

  /// Ενημερώνει μια υπάρχουσα εγγραφή στον πίνακα tasks.
  Future<void> updateTask(Task task) async {
    if (task.id == null) return;
    final db = await _db;
    final tid = task.id!;
    final oldRows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [tid],
      limit: 1,
    );
    final oldRow = oldRows.isEmpty ? null : Map<String, dynamic>.from(oldRows.first);

    final map = task.toMap();
    map.remove('id');
    if (!await _hasSnoozeHistoryColumn(db)) {
      map.remove('snooze_history_json');
    }
    map['updated_at'] = DateTime.now().toIso8601String();
    map['search_index'] = SearchTextNormalizer.normalizeForSearch(
      task.combinedSearchText,
    );
    final n = await db.update('tasks', map, where: 'id = ?', whereArgs: [tid]);
    if (n > 0 && oldRow != null) {
      await _auditTaskUpdate(db, tid, oldRow, map);
    }
  }

  /// Soft delete εγγραφής βάσει ID (audit στο [DirectoryRepository]).
  Future<void> deleteTask(int id) async {
    final dbDel = await DatabaseHelper.instance.database;
    await DirectoryRepository(dbDel).softDeleteTask(id);
  }

  /// Ορίζει status = closed, solution_notes και updated_at.
  Future<void> closeTask(int id, String solutionNotes) async {
    final db = await _db;
    final oldRows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final oldStatus =
        oldRows.isEmpty ? null : oldRows.first['status'] as String?;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'tasks',
      {'status': 'closed', 'solution_notes': solutionNotes, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      final user = await AuditService.performingUser(db);
      await AuditService.log(
        db,
        action: 'ΚΛΕΙΣΙΜΟ ΕΚΚΡΕΜΟΤΗΤΑΣ',
        userPerforming: user,
        details: 'tasks id=$id',
        entityType: AuditEntityTypes.task,
        entityId: id,
        oldValues: oldStatus != null ? {'status': oldStatus} : null,
        newValues: {
          'status': 'closed',
          'solution_notes': solutionNotes,
        },
      );
    } catch (_) {}
  }

  /// Κλήσεις με status pending που δεν έχουν αντίστοιχο task.
  Future<List<OrphanCall>> getCallsWithoutTask() async {
    final db = await _db;
    // Ορφανή = pending κλήση χωρίς καμία εγγραφή στο `tasks` για αυτό το `call_id`.
    // Αν υπήρχε task (ακόμη και soft-deleted), δεν ξαναπροτείνουμε μαζική δημιουργία.
    final rows = await db.rawQuery('''
      SELECT c.id, c.date, c.time, c.caller_id, c.caller_text, c.issue
      FROM calls c
      WHERE c.status = 'pending'
        AND COALESCE(c.is_deleted, 0) = 0
        AND NOT EXISTS (SELECT 1 FROM tasks t WHERE t.call_id = c.id)
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
