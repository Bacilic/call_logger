import 'dart:convert';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/tasks/models/task.dart';
import '../../features/tasks/models/task_analytics_summary.dart';
import '../../features/tasks/utils/task_overdue_timeline.dart';
import 'audit_service.dart';
import 'database_helper.dart';

/// Η Ανάλυση εκκρεμοτήτων: πλήθη, ποσοστά, προέλευση και καμπύλες ανά ημέρα.
///
/// Μόνο αναγνώσεις — καμία εγγραφή δεν περνά από εδώ. Οι εγγραφές ζουν στο
/// [TasksRepository], που προωθεί εδώ τις δύο ερωτήσεις της αναφοράς.
class TasksAnalyticsRepository {
  const TasksAnalyticsRepository(this.db);

  final Database db;

  /// Ελάχιστη/μέγιστη ημερομηνία δημιουργίας εκκρεμοτήτων (ημέρα μόνο).
  Future<({DateTime start, DateTime end})> getTaskCreationDateSpan() async {
    final rows = await db.rawQuery('''
      SELECT MIN(created_at) AS min_created, MAX(created_at) AS max_created
      FROM tasks
      WHERE COALESCE(is_deleted, 0) = 0
        AND created_at IS NOT NULL
        AND TRIM(created_at) != ''
      ''');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (rows.isEmpty) {
      return (start: today, end: today);
    }
    final minRaw = rows.first['min_created'];
    final maxRaw = rows.first['max_created'];
    if (minRaw == null || maxRaw == null) {
      return (start: today, end: today);
    }
    final minDt = DateTime.tryParse(minRaw.toString());
    final maxDt = DateTime.tryParse(maxRaw.toString());
    if (minDt == null || maxDt == null) {
      return (start: today, end: today);
    }
    return (
      start: DateTime(minDt.year, minDt.month, minDt.day),
      end: DateTime(maxDt.year, maxDt.month, maxDt.day),
    );
  }

  /// Η στιγμή ολοκλήρωσης μιας κλειστής εκκρεμότητας, σε SQL.
  ///
  /// Το `completed_at` σφραγίζεται **μόνο** στη μετάβαση προς «ολοκληρωμένη»
  /// και δεν κουνιέται από μεταγενέστερες διορθώσεις κειμένου· το `updated_at`
  /// κουνιέται με κάθε αποθήκευση. Ένα ορθογραφικό που διορθώθηκε έξι μέρες
  /// αργότερα δεν είναι νέα ολοκλήρωση.
  ///
  /// Η εφεδρεία στο `updated_at` αφορά εγγραφές που γεννήθηκαν πριν υπάρξει
  /// σφραγίδα: καλύτερα μια προσέγγιση παρά ολοκλήρωση που εξαφανίζεται από τα
  /// στατιστικά.
  ///
  /// Γράφεται μία φορά και χρησιμοποιείται από **κάθε** ερώτημα ολοκληρώσεων,
  /// ώστε ένα μελλοντικό ερώτημα να μην μπορεί να ξεχάσει τον κανόνα.
  static const String _completionMoment = 'COALESCE(completed_at, updated_at)';

  Future<TaskAnalyticsSummary> getTaskAnalytics(DateTimeRange range) async {
    final normalized = _normalizeRange(range);
    final start = normalized.start;
    final end = normalized.end;
    final endExclusive = normalized.endExclusive;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final startIso = start.toIso8601String();
    final endExclusiveIso = endExclusive.toIso8601String();

    Future<int> countByQuery(String sql, List<Object?> args) async {
      final rows = await db.rawQuery(sql, args);
      if (rows.isEmpty) return 0;
      final n = rows.first['count'];
      return n is int ? n : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
    }

    final activeNowCount = await countByQuery(
      "SELECT COUNT(*) AS count FROM tasks "
      "WHERE status IN ('open', 'snoozed') AND COALESCE(is_deleted, 0) = 0",
      const [],
    );
    final createdInRangeCount = await countByQuery(
      "SELECT COUNT(*) AS count FROM tasks "
      "WHERE COALESCE(is_deleted, 0) = 0 "
      "AND created_at >= ? AND created_at < ?",
      [startIso, endExclusiveIso],
    );
    final activeCreatedInRangeCount = await countByQuery(
      "SELECT COUNT(*) AS count FROM tasks "
      "WHERE status IN ('open', 'snoozed') AND COALESCE(is_deleted, 0) = 0 "
      "AND created_at >= ? AND created_at < ?",
      [startIso, endExclusiveIso],
    );
    final closedInRangeCount = await countByQuery(
      "SELECT COUNT(*) AS count FROM tasks "
      "WHERE status = 'closed' AND COALESCE(is_deleted, 0) = 0 "
      "AND $_completionMoment >= ? AND $_completionMoment < ?",
      [startIso, endExclusiveIso],
    );
    final cancelledInRangeCount = await countByQuery(
      "SELECT COUNT(*) AS count FROM audit_log "
      "WHERE entity_type = ? AND action = ? "
      "AND timestamp >= ? AND timestamp < ?",
      [
        AuditEntityTypes.task,
        DatabaseHelper.auditActionDelete,
        startIso,
        endExclusiveIso,
      ],
    );
    // Η τύχη όσων ΑΝΟΙΞΑΝ στο διάστημα, ως το τέλος του: ολοκληρώθηκαν,
    // ακυρώθηκαν ή εκκρεμούν. Τα ποσοστά βγαίνουν από αυτές και μόνο, οπότε
    // δεν ξεπερνούν ποτέ το 100% — όσο κι αν κλείσουν παλιότερες.
    final openedRows = await db.rawQuery(
      "SELECT COUNT(*) AS opened, "
      "COALESCE(SUM(CASE WHEN COALESCE(t.is_deleted, 0) = 0 "
      "AND t.status = 'closed' AND $_completionMoment < ? "
      "THEN 1 ELSE 0 END), 0) AS closed, "
      "COALESCE(SUM(CASE WHEN COALESCE(t.is_deleted, 0) = 1 AND COALESCE(("
      "SELECT MIN(a.timestamp) FROM audit_log a "
      "WHERE a.entity_type = ? AND a.action = ? AND a.entity_id = t.id"
      "), '') < ? THEN 1 ELSE 0 END), 0) AS cancelled "
      "FROM tasks t WHERE t.created_at >= ? AND t.created_at < ?",
      [
        endExclusiveIso,
        AuditEntityTypes.task,
        DatabaseHelper.auditActionDelete,
        endExclusiveIso,
        startIso,
        endExclusiveIso,
      ],
    );
    int openedCount(String column) {
      final n = openedRows.isEmpty ? null : openedRows.first[column];
      return n is int ? n : (n is num ? n.toInt() : 0);
    }

    final openedInRange = openedCount('opened');
    final openedThenClosed = openedCount('closed');
    final openedThenCancelled = openedCount('cancelled');
    final overdueActiveCount = await countByQuery(
      "SELECT COUNT(*) AS count FROM tasks "
      "WHERE status IN ('open', 'snoozed') AND COALESCE(is_deleted, 0) = 0 "
      "AND due_date < ?",
      [nowIso],
    );
    // Καθυστερημένη του διαστήματος = έμεινε ανοιχτή μετά από κάποια προθεσμία
    // της. Όχι «η προθεσμία είναι πριν από τώρα»: μια εκκρεμότητα που έκλεισε
    // εγκαίρως έχει κι αυτή περασμένη προθεσμία, και δεν άργησε.
    final rangeTaskRows = await db.rawQuery(
      "SELECT due_date, snooze_history_json, "
      "CASE WHEN status = 'closed' THEN $_completionMoment END "
      "AS completed_moment "
      "FROM tasks "
      "WHERE COALESCE(is_deleted, 0) = 0 "
      "AND created_at >= ? AND created_at < ?",
      [startIso, endExclusiveIso],
    );
    final overdueInRangeCount = rangeTaskRows.where((row) {
      DateTime? parse(Object? v) =>
          v == null ? null : DateTime.tryParse(v.toString());
      return TaskOverdueTimeline.wasEverOverdue(
        now: now,
        endedAt: parse(row['completed_moment']),
        currentDue: parse(row['due_date']),
        snoozes: TaskSnoozeEntry.parseHistory(
          row['snooze_history_json'] as String?,
        ),
      );
    }).length;

    final avgCompletionRows = await db.rawQuery(
      "SELECT AVG((julianday($_completionMoment) - julianday(created_at)) * 86400.0) AS avg_seconds "
      "FROM tasks "
      "WHERE status = 'closed' AND COALESCE(is_deleted, 0) = 0 "
      "AND created_at IS NOT NULL AND $_completionMoment IS NOT NULL "
      "AND $_completionMoment >= ? AND $_completionMoment < ?",
      [startIso, endExclusiveIso],
    );
    final avgCompletionSeconds = avgCompletionRows.isEmpty
        ? 0.0
        : ((avgCompletionRows.first['avg_seconds'] as num?)?.toDouble() ?? 0.0);

    final originRows = await db.rawQuery(
      "SELECT COALESCE(NULLIF(TRIM(origin), ''), ?) AS origin, COUNT(*) AS count "
      "FROM tasks "
      "WHERE COALESCE(is_deleted, 0) = 0 "
      "AND created_at >= ? AND created_at < ? "
      "GROUP BY COALESCE(NULLIF(TRIM(origin), ''), ?)",
      [Task.originLegacy, startIso, endExclusiveIso, Task.originLegacy],
    );
    final originTotal = originRows.fold<int>(0, (sum, row) {
      final n = row['count'];
      return sum +
          (n is int ? n : (n is num ? n.toInt() : int.tryParse('$n') ?? 0));
    });
    final originDistribution = originRows.map((row) {
      final normalizedOrigin = Task.normalizeOrigin(row['origin'] as String?);
      final n = row['count'];
      final count = n is int
          ? n
          : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
      final percent = originTotal == 0 ? 0.0 : (count / originTotal) * 100;
      return TaskAnalyticsOriginSlice(
        origin: normalizedOrigin,
        label: _originLabel(normalizedOrigin),
        count: count,
        percent: percent,
      );
    }).toList()..sort((a, b) => b.count.compareTo(a.count));

    final snoozeRows = await db.rawQuery(
      "SELECT snooze_history_json FROM tasks "
      "WHERE COALESCE(is_deleted, 0) = 0 "
      "AND created_at >= ? AND created_at < ?",
      [startIso, endExclusiveIso],
    );
    var snoozeEntriesTotal = 0;
    for (final row in snoozeRows) {
      snoozeEntriesTotal += _countSnoozeEntries(row['snooze_history_json']);
    }
    final avgSnoozesPerTask = snoozeRows.isEmpty
        ? 0.0
        : snoozeEntriesTotal / snoozeRows.length;

    final createdByDayRows = await db.rawQuery(
      "SELECT SUBSTR(created_at, 1, 10) AS day, COUNT(*) AS count "
      "FROM tasks "
      "WHERE COALESCE(is_deleted, 0) = 0 "
      "AND created_at >= ? AND created_at < ? "
      "GROUP BY SUBSTR(created_at, 1, 10)",
      [startIso, endExclusiveIso],
    );
    final closedByDayRows = await db.rawQuery(
      "SELECT SUBSTR($_completionMoment, 1, 10) AS day, COUNT(*) AS count "
      "FROM tasks "
      "WHERE status = 'closed' AND COALESCE(is_deleted, 0) = 0 "
      "AND $_completionMoment >= ? AND $_completionMoment < ? "
      "GROUP BY SUBSTR($_completionMoment, 1, 10)",
      [startIso, endExclusiveIso],
    );
    final createdByDay = _countMapByDay(createdByDayRows);
    final closedByDay = _countMapByDay(closedByDayRows);
    final backlogGrowth = <TaskAnalyticsBacklogPoint>[];
    var runningDelta = 0;
    final totalDays = end.difference(start).inDays + 1;
    for (var i = 0; i < totalDays; i++) {
      final day = start.add(Duration(days: i));
      final key = _dayKey(day);
      final createdCount = createdByDay[key] ?? 0;
      final closedCount = closedByDay[key] ?? 0;
      final delta = createdCount - closedCount;
      runningDelta += delta;
      backlogGrowth.add(
        TaskAnalyticsBacklogPoint(
          date: day,
          createdCount: createdCount,
          closedCount: closedCount,
          delta: delta,
          runningDelta: runningDelta,
        ),
      );
    }

    final sparkEnd = DateTime(end.year, end.month, end.day);
    final sparkStart = sparkEnd.subtract(const Duration(days: 6));
    final sparkData = await _buildSparklines(
      db,
      start: sparkStart,
      end: sparkEnd,
    );

    final overdueRateActive = activeNowCount == 0
        ? 0.0
        : (overdueActiveCount / activeNowCount) * 100;
    final overdueRateRange = createdInRangeCount == 0
        ? 0.0
        : (overdueInRangeCount / createdInRangeCount) * 100;
    final completionRateInRange = openedInRange == 0
        ? 0.0
        : (openedThenClosed / openedInRange) * 100;
    final cancellationRateInRange = openedInRange == 0
        ? 0.0
        : (openedThenCancelled / openedInRange) * 100;

    return TaskAnalyticsSummary(
      rangeStart: start,
      rangeEnd: end,
      activeNowCount: activeNowCount,
      activeCreatedInRangeCount: activeCreatedInRangeCount,
      createdInRangeCount: createdInRangeCount,
      closedInRangeCount: closedInRangeCount,
      cancelledInRangeCount: cancelledInRangeCount,
      overdueActiveCount: overdueActiveCount,
      overdueInRangeCount: overdueInRangeCount,
      overdueRateActive: overdueRateActive,
      overdueRateRange: overdueRateRange,
      completionRateInRange: completionRateInRange,
      cancellationRateInRange: cancellationRateInRange,
      avgCompletionSeconds: avgCompletionSeconds,
      avgSnoozesPerTask: avgSnoozesPerTask,
      originDistribution: originDistribution,
      backlogGrowth: backlogGrowth,
      sparklineActive: sparkData.active,
      sparklineClosed: sparkData.closed,
      sparklineCancelled: sparkData.cancelled,
      sparklineOverdue: sparkData.overdue,
      sparklineSnoozes: sparkData.snoozes,
    );
  }

  ({DateTime start, DateTime end, DateTime endExclusive}) _normalizeRange(
    DateTimeRange range,
  ) {
    var start = DateTime(range.start.year, range.start.month, range.start.day);
    var end = DateTime(range.end.year, range.end.month, range.end.day);
    if (end.isBefore(start)) {
      final tmp = start;
      start = end;
      end = tmp;
    }
    final endExclusive = end.add(const Duration(days: 1));
    return (start: start, end: end, endExclusive: endExclusive);
  }

  Map<String, int> _countMapByDay(List<Map<String, Object?>> rows) {
    final map = <String, int>{};
    for (final row in rows) {
      final day = (row['day'] as String?)?.trim();
      if (day == null || day.isEmpty) continue;
      final n = row['count'];
      final count = n is int
          ? n
          : (n is num ? n.toInt() : int.tryParse('$n') ?? 0);
      map[day] = count;
    }
    return map;
  }

  String _dayKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int _countSnoozeEntries(Object? raw) {
    final text = raw?.toString();
    if (text == null || text.trim().isEmpty) return 0;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return 0;
      var count = 0;
      for (final item in decoded) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          if (map['snoozedAt'] != null || map['dueAt'] != null) {
            count++;
          }
          continue;
        }
        if (DateTime.tryParse(item.toString()) != null) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  String _originLabel(String origin) {
    return switch (origin) {
      Task.originManualFab => 'Χειροκίνητη',
      Task.originCallLinked => 'Από κλήση',
      Task.originQuickAdd => 'Quick add',
      _ => 'Legacy',
    };
  }

  Future<
    ({
      List<double> active,
      List<double> closed,
      List<double> cancelled,
      List<double> overdue,
      List<double> snoozes,
    })
  >
  _buildSparklines(
    Database db, {
    required DateTime start,
    required DateTime end,
  }) async {
    final startIso = start.toIso8601String();
    final endExclusiveIso = end.add(const Duration(days: 1)).toIso8601String();
    final closedRows = await db.rawQuery(
      "SELECT SUBSTR($_completionMoment, 1, 10) AS day, COUNT(*) AS count "
      "FROM tasks "
      "WHERE status = 'closed' AND COALESCE(is_deleted, 0) = 0 "
      "AND $_completionMoment >= ? AND $_completionMoment < ? "
      "GROUP BY SUBSTR($_completionMoment, 1, 10)",
      [startIso, endExclusiveIso],
    );
    final cancelledRows = await db.rawQuery(
      "SELECT SUBSTR(timestamp, 1, 10) AS day, COUNT(*) AS count "
      "FROM audit_log "
      "WHERE entity_type = ? AND action = ? "
      "AND timestamp >= ? AND timestamp < ? "
      "GROUP BY SUBSTR(timestamp, 1, 10)",
      [
        AuditEntityTypes.task,
        DatabaseHelper.auditActionDelete,
        startIso,
        endExclusiveIso,
      ],
    );
    // Όσες εκκρεμούσαν έστω και μία μέρα του παραθύρου — και όσες έκλεισαν ή
    // διαγράφηκαν αργότερα: εκείνες τις μέρες ήταν ακόμη ανοιχτές. Από αυτές
    // κρίνονται, ανά μέρα και χωρίς νέο ερώτημα, και η καμπύλη ενεργών και η
    // καμπύλη καθυστερημένων.
    final overdueRows = await db.rawQuery(
      "SELECT * FROM ("
      "SELECT t.created_at, t.due_date, t.snooze_history_json, t.status, "
      "COALESCE(t.is_deleted, 0) AS deleted, "
      "CASE WHEN t.status = 'closed' THEN $_completionMoment END "
      "AS completed_moment, "
      "CASE WHEN COALESCE(t.is_deleted, 0) = 1 THEN ("
      "SELECT MIN(a.timestamp) FROM audit_log a "
      "WHERE a.entity_type = ? AND a.action = ? AND a.entity_id = t.id"
      ") END AS deleted_moment "
      "FROM tasks t WHERE t.created_at < ?"
      ") WHERE (deleted = 0 AND (status IN ('open', 'snoozed') "
      "OR completed_moment >= ?)) "
      "OR (deleted = 1 AND deleted_moment >= ?)",
      [
        AuditEntityTypes.task,
        DatabaseHelper.auditActionDelete,
        endExclusiveIso,
        startIso,
        startIso,
      ],
    );
    final timelines = [
      for (final row in overdueRows) ?_overdueTimelineFrom(row),
    ];
    final closedByDay = _countMapByDay(closedRows);
    final cancelledByDay = _countMapByDay(cancelledRows);
    final snoozeRows = await db.rawQuery(
      "SELECT snooze_history_json FROM tasks "
      "WHERE COALESCE(is_deleted, 0) = 0 "
      "AND COALESCE(snooze_history_json, '') <> '' AND created_at < ?",
      [endExclusiveIso],
    );
    final snoozesByDay = <String, int>{};
    for (final row in snoozeRows) {
      for (final snooze in TaskSnoozeEntry.parseHistory(
        row['snooze_history_json'] as String?,
      )) {
        final key = _dayKey(snooze.snoozedAt);
        snoozesByDay[key] = (snoozesByDay[key] ?? 0) + 1;
      }
    }

    final active = <double>[];
    final closed = <double>[];
    final cancelled = <double>[];
    final overdue = <double>[];
    final snoozes = <double>[];
    final totalDays = end.difference(start).inDays + 1;
    for (var i = 0; i < totalDays; i++) {
      final day = start.add(Duration(days: i));
      final dayEnd = day.add(const Duration(days: 1));
      final key = _dayKey(day);
      final cClosed = (closedByDay[key] ?? 0).toDouble();
      final cCancelled = (cancelledByDay[key] ?? 0).toDouble();
      active.add(
        timelines
            .where(
              (t) => TaskOverdueTimeline.wasOpenAt(
                dayEnd,
                createdAt: t.createdAt,
                endedAt: t.endedAt,
              ),
            )
            .length
            .toDouble(),
      );
      closed.add(cClosed);
      cancelled.add(cCancelled);
      snoozes.add((snoozesByDay[key] ?? 0).toDouble());
      overdue.add(
        timelines
            .where(
              (t) => TaskOverdueTimeline.wasOverdueAt(
                dayEnd,
                createdAt: t.createdAt,
                endedAt: t.endedAt,
                currentDue: t.currentDue,
                snoozes: t.snoozes,
              ),
            )
            .length
            .toDouble(),
      );
    }
    return (
      active: active,
      closed: closed,
      cancelled: cancelled,
      overdue: overdue,
      snoozes: snoozes,
    );
  }

  /// Τα στοιχεία που χρειάζεται η κρίση «ήταν καθυστερημένη εκείνη τη μέρα;».
  /// Εγγραφή χωρίς αναγνώσιμη ημερομηνία δημιουργίας δεν μετρά.
  static ({
    DateTime createdAt,
    DateTime? endedAt,
    DateTime? currentDue,
    List<TaskSnoozeEntry> snoozes,
  })?
  _overdueTimelineFrom(Map<String, Object?> row) {
    DateTime? parse(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    final createdAt = parse(row['created_at']);
    if (createdAt == null) return null;
    final completed = parse(row['completed_moment']);
    final deleted = parse(row['deleted_moment']);
    final endedAt = completed == null
        ? deleted
        : (deleted != null && deleted.isBefore(completed)
              ? deleted
              : completed);
    return (
      createdAt: createdAt,
      endedAt: endedAt,
      currentDue: parse(row['due_date']),
      snoozes: TaskSnoozeEntry.parseHistory(
        row['snooze_history_json'] as String?,
      ),
    );
  }
}
