part of 'calls_repository.dart';

mixin CallsRepositoryDashboardMixin on CallsRepositoryCore {
  void _appendDashboardUserFilter(
    List<String> whereClauses,
    List<dynamic> args,
    String userPhoneExpr,
    String userQuery,
  ) {
    final nq = SearchTextNormalizer.normalizeForSearch(userQuery);
    if (nq.isEmpty) return;
    whereClauses.add('(calls.search_index LIKE ? OR $userPhoneExpr LIKE ?)');
    args.add('%$nq%');
    args.add('%$nq%');
  }
  /// Στατιστικά κλήσεων για πίνακα ελέγχου: KPIs, ανά τμήμα, ανά βλάβη (`issue`).
  Future<DashboardSummaryModel> getDashboardStatistics(
    DashboardFilterModel filter,
  ) async {
    const userPhoneExpr =
        "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";
    const deptExpr = "COALESCE(departments.name, calls.department_text, '-')";
    const equipExpr =
        "COALESCE(equipment.code_equipment, calls.equipment_text, '')";
    const callerNameExpr =
        "TRIM(COALESCE(users.first_name, '') || ' ' || COALESCE(users.last_name, ''))";
    const callerLabelExpr =
        "CASE WHEN TRIM($callerNameExpr) = '' "
        "THEN COALESCE(NULLIF(TRIM(calls.caller_text), ''), '-') "
        "ELSE TRIM($callerNameExpr) END";

    final whereClausesBase = <String>['COALESCE(calls.is_deleted, 0) = 0'];
    final argsBase = <dynamic>[];

    final dept = filter.department?.trim();
    if (dept != null && dept.isNotEmpty) {
      whereClausesBase.add('$deptExpr = ?');
      argsBase.add(dept);
    }

    final userQ = filter.userName?.trim();
    if (userQ != null && userQ.isNotEmpty) {
      _appendDashboardUserFilter(
        whereClausesBase,
        argsBase,
        userPhoneExpr,
        userQ,
      );
    }

    final eqQ = filter.equipmentCode?.trim();
    if (eqQ != null && eqQ.isNotEmpty) {
      whereClausesBase.add('$equipExpr LIKE ?');
      argsBase.add('%$eqQ%');
    }

    final kw = filter.keyword.trim();
    if (kw.isNotEmpty) {
      final nk = SearchTextNormalizer.normalizeForSearch(kw);
      if (nk.isNotEmpty) {
        whereClausesBase.add('calls.search_index LIKE ?');
        argsBase.add('%$nk%');
      }
    }

    final whereClauses = List<String>.from(whereClausesBase);
    final args = List<dynamic>.from(argsBase);
    final df = filter.dateFromSql;
    final dt = filter.dateToSql;
    final isAllDatesMode =
        (df == null || df.isEmpty) && (dt == null || dt.isEmpty);
    if (df != null && df.isNotEmpty) {
      whereClauses.add('calls.date >= ?');
      args.add(df);
    }
    if (dt != null && dt.isNotEmpty) {
      whereClauses.add('calls.date <= ?');
      args.add(dt);
    }
    final whereSql = 'WHERE ${whereClauses.join(' AND ')}';

    final fromJoin =
        '''
FROM calls
LEFT JOIN categories cat ON cat.id = calls.category_id
LEFT JOIN users ON calls.caller_id = users.id
LEFT JOIN (
  SELECT up.user_id AS uid,
         GROUP_CONCAT(p.number, ', ') AS phone_list
  FROM user_phones up
  JOIN phones p ON p.id = up.phone_id
  GROUP BY up.user_id
) upl ON upl.uid = users.id
LEFT JOIN equipment ON calls.equipment_id = equipment.id
LEFT JOIN departments ON users.department_id = departments.id
$whereSql
''';

    final kpiRows = await db.rawQuery('''
      SELECT COUNT(*) AS c,
             COALESCE(SUM(calls.duration), 0) AS total_dur,
             AVG(calls.duration) AS avg_dur
      $fromJoin
      ''', args);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final anchorDate =
        filter.dateTo ??
        filter.dateFrom ??
        DateTime(today.year, today.month, today.day);
    final anchorDay = DateTime(
      anchorDate.year,
      anchorDate.month,
      anchorDate.day,
    );
    final anchorDaySql = DateFormat('yyyy-MM-dd').format(anchorDay);
    final previousDay = anchorDay.subtract(const Duration(days: 1));
    final previousDaySql = DateFormat('yyyy-MM-dd').format(previousDay);

    final List<Map<String, dynamic>> previousKpiRows;
    if (isAllDatesMode) {
      previousKpiRows = const [];
    } else {
      final prevRange = filter.previousComparisonRangeInclusive;
      final wherePreviousPeriod = List<String>.from(whereClausesBase);
      final argsPreviousPeriod = List<dynamic>.from(argsBase);
      if (prevRange != null) {
        wherePreviousPeriod.add('calls.date >= ?');
        argsPreviousPeriod.add(
          DateFormat('yyyy-MM-dd').format(prevRange.start),
        );
        wherePreviousPeriod.add('calls.date <= ?');
        argsPreviousPeriod.add(DateFormat('yyyy-MM-dd').format(prevRange.end));
      } else {
        wherePreviousPeriod.add('calls.date = ?');
        argsPreviousPeriod.add(previousDaySql);
      }
      final fromJoinPreviousPeriod =
          '''
FROM calls
LEFT JOIN categories cat ON cat.id = calls.category_id
LEFT JOIN users ON calls.caller_id = users.id
LEFT JOIN (
  SELECT up.user_id AS uid,
         GROUP_CONCAT(p.number, ', ') AS phone_list
  FROM user_phones up
  JOIN phones p ON p.id = up.phone_id
  GROUP BY up.user_id
) upl ON upl.uid = users.id
LEFT JOIN equipment ON calls.equipment_id = equipment.id
LEFT JOIN departments ON users.department_id = departments.id
WHERE ${wherePreviousPeriod.join(' AND ')}
''';
      previousKpiRows = await db.rawQuery('''
      SELECT COUNT(*) AS c,
             COALESCE(SUM(calls.duration), 0) AS total_dur,
             AVG(calls.duration) AS avg_dur
      $fromJoinPreviousPeriod
      ''', argsPreviousPeriod);
    }

    final deptRows = await db.rawQuery('''
      SELECT $deptExpr AS dept_name,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      $fromJoin
      GROUP BY $deptExpr
      ORDER BY cnt DESC
      ''', args);

    const categoryNameRawExpr =
        "COALESCE(NULLIF(TRIM(cat.name), ''), NULLIF(TRIM(calls.category_text), ''))";
    final escapedNoCategory =
        kDashboardNoCategoryLabel.replaceAll("'", "''");
    final categoryLabelExpr =
        "CASE WHEN $categoryNameRawExpr IS NULL "
        "THEN '$escapedNoCategory' "
        "ELSE $categoryNameRawExpr END";

    final issueRows = await db.rawQuery('''
      SELECT $categoryLabelExpr AS issue_label,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      $fromJoin
      GROUP BY $categoryLabelExpr
      ORDER BY cnt DESC
      LIMIT 15
      ''', args);

    final trendStart = anchorDay.subtract(const Duration(days: 6));
    final trendStartSql = DateFormat('yyyy-MM-dd').format(trendStart);
    final whereTrend = List<String>.from(whereClausesBase)
      ..add('calls.date >= ?')
      ..add('calls.date <= ?');
    final argsTrend = List<dynamic>.from(argsBase)
      ..add(trendStartSql)
      ..add(anchorDaySql);
    final fromJoinTrend =
        '''
FROM calls
LEFT JOIN categories cat ON cat.id = calls.category_id
LEFT JOIN users ON calls.caller_id = users.id
LEFT JOIN (
  SELECT up.user_id AS uid,
         GROUP_CONCAT(p.number, ', ') AS phone_list
  FROM user_phones up
  JOIN phones p ON p.id = up.phone_id
  GROUP BY up.user_id
) upl ON upl.uid = users.id
LEFT JOIN equipment ON calls.equipment_id = equipment.id
LEFT JOIN departments ON users.department_id = departments.id
WHERE ${whereTrend.join(' AND ')}
''';
    final trendRows = await db.rawQuery('''
      SELECT calls.date AS day,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      $fromJoinTrend
      GROUP BY calls.date
      ORDER BY calls.date ASC
      ''', argsTrend);

    final topCallerRows = await db.rawQuery('''
      SELECT $callerLabelExpr AS caller_name,
             COUNT(*) AS cnt
      $fromJoin
      GROUP BY $callerLabelExpr
      ORDER BY cnt DESC, caller_name ASC
      LIMIT 10
      ''', args);

    final longestRows = await db.rawQuery('''
      SELECT $callerLabelExpr AS caller_name,
             $deptExpr AS dept_name,
             COALESCE(calls.duration, 0) AS dur
      $fromJoin
      ORDER BY dur DESC, caller_name ASC
      LIMIT 20
      ''', args);

    final hourRows = await db.rawQuery('''
      SELECT CAST(SUBSTR(COALESCE(calls.time, '00:00'), 1, 2) AS INTEGER) AS hh,
             COUNT(*) AS cnt
      $fromJoin
      GROUP BY hh
      ORDER BY hh ASC
      ''', args);

    final kpi = kpiRows.isEmpty ? <String, dynamic>{} : kpiRows.first;
    final previousKpi = previousKpiRows.isEmpty
        ? <String, dynamic>{}
        : previousKpiRows.first;
    final totalCalls = (kpi['c'] as num?)?.toInt() ?? 0;
    final totalDurationSeconds = (kpi['total_dur'] as num?)?.toInt() ?? 0;
    final avgDurationSeconds = totalCalls == 0
        ? 0.0
        : ((kpi['avg_dur'] as num?)?.toDouble() ?? 0.0);
    final previousPeriodTotalCalls = (previousKpi['c'] as num?)?.toInt() ?? 0;
    final previousPeriodTotalDurationSeconds =
        (previousKpi['total_dur'] as num?)?.toInt() ?? 0;
    final previousPeriodAvgDurationSeconds = previousPeriodTotalCalls == 0
        ? 0.0
        : ((previousKpi['avg_dur'] as num?)?.toDouble() ?? 0.0);

    final byDepartment = deptRows
        .map(
          (row) => DepartmentStat(
            name: (row['dept_name'] as String?)?.trim().isNotEmpty == true
                ? (row['dept_name'] as String).trim()
                : '-',
            count: (row['cnt'] as num?)?.toInt() ?? 0,
            sumDurationSeconds: (row['sum_dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    final byIssue = issueRows
        .map(
          (row) => IssueStat(
            name: (row['issue_label'] as String?)?.trim() ?? '',
            count: (row['cnt'] as num?)?.toInt() ?? 0,
            sumDurationSeconds: (row['sum_dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    final trendByDate = <String, Map<String, dynamic>>{
      for (final row in trendRows) (row['day'] as String? ?? ''): row,
    };
    final dailyTrend = List<DailyTrendPoint>.generate(7, (index) {
      final day = trendStart.add(Duration(days: index));
      final dayKey = DateFormat('yyyy-MM-dd').format(day);
      final row = trendByDate[dayKey];
      return DailyTrendPoint(
        date: day,
        callCount: (row?['cnt'] as num?)?.toInt() ?? 0,
        totalDurationSeconds: (row?['sum_dur'] as num?)?.toInt() ?? 0,
      );
    });

    final sparkStart = anchorDay.subtract(const Duration(days: 6));
    final sparkStartSql = DateFormat('yyyy-MM-dd').format(sparkStart);
    final todaySql = DateFormat('yyyy-MM-dd').format(anchorDay);
    final whereSpark = List<String>.from(whereClausesBase)
      ..add('calls.date >= ?')
      ..add('calls.date <= ?');
    final argsSpark = List<dynamic>.from(argsBase)
      ..add(sparkStartSql)
      ..add(todaySql);
    final fromJoinSpark =
        '''
FROM calls
LEFT JOIN categories cat ON cat.id = calls.category_id
LEFT JOIN users ON calls.caller_id = users.id
LEFT JOIN (
  SELECT up.user_id AS uid,
         GROUP_CONCAT(p.number, ', ') AS phone_list
  FROM user_phones up
  JOIN phones p ON p.id = up.phone_id
  GROUP BY up.user_id
) upl ON upl.uid = users.id
LEFT JOIN equipment ON calls.equipment_id = equipment.id
LEFT JOIN departments ON users.department_id = departments.id
WHERE ${whereSpark.join(' AND ')}
''';
    final sparkRows = await db.rawQuery('''
      SELECT calls.date AS day,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      $fromJoinSpark
      GROUP BY calls.date
      ORDER BY calls.date ASC
      ''', argsSpark);
    final sparkByDate = <String, Map<String, dynamic>>{
      for (final row in sparkRows) (row['day'] as String? ?? ''): row,
    };
    final sparklineLast7Days = List<DailyTrendPoint>.generate(7, (index) {
      final day = sparkStart.add(Duration(days: index));
      final dayKey = DateFormat('yyyy-MM-dd').format(day);
      final row = sparkByDate[dayKey];
      return DailyTrendPoint(
        date: day,
        callCount: (row?['cnt'] as num?)?.toInt() ?? 0,
        totalDurationSeconds: (row?['sum_dur'] as num?)?.toInt() ?? 0,
      );
    });

    final topCallers = topCallerRows
        .map(
          (row) => CallerStat(
            name: (row['caller_name'] as String?)?.trim().isNotEmpty == true
                ? (row['caller_name'] as String).trim()
                : '-',
            count: (row['cnt'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    final longestCalls = longestRows
        .map(
          (row) => LongestCallEntry(
            callerName:
                (row['caller_name'] as String?)?.trim().isNotEmpty == true
                ? (row['caller_name'] as String).trim()
                : '-',
            department: (row['dept_name'] as String?)?.trim().isNotEmpty == true
                ? (row['dept_name'] as String).trim()
                : '-',
            durationSeconds: (row['dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    final hourCountMap = <int, int>{
      for (final row in hourRows)
        (row['hh'] as num?)?.toInt() ?? 0: (row['cnt'] as num?)?.toInt() ?? 0,
    };
    final hourlyDistribution = List<HourlyBucket>.generate(
      24,
      (hour) => HourlyBucket(hour: hour, callCount: hourCountMap[hour] ?? 0),
    );

    var totalActiveDays = 0;
    var medianDurationSeconds = 0;
    DateTime? historyDateFrom;
    DateTime? historyDateTo;
    KpiAllDatesBarSparklines? allDatesBarSparklines;
    if (isAllDatesMode && totalCalls > 0) {
      final activeDaysRows = await db.rawQuery('''
        SELECT COUNT(DISTINCT calls.date) AS active_days,
               MIN(calls.date) AS min_date,
               MAX(calls.date) AS max_date
        $fromJoin
        ''', args);
      final activeRow = activeDaysRows.isEmpty ? null : activeDaysRows.first;
      totalActiveDays = (activeRow?['active_days'] as num?)?.toInt() ?? 0;
      historyDateFrom = parseDashboardSqlDate(
        activeRow?['min_date'] as String?,
      );
      historyDateTo = parseDashboardSqlDate(activeRow?['max_date'] as String?);

      final durationRows = await db.rawQuery('''
        SELECT calls.duration AS dur
        $fromJoin
        ORDER BY calls.duration ASC
        ''', args);
      final durations = durationRows
          .map((row) => (row['dur'] as num?)?.toInt() ?? 0)
          .toList(growable: false);
      medianDurationSeconds = medianDurationSecondsFromList(durations);

      final monthRows = await db.rawQuery('''
        SELECT strftime('%Y-%m', calls.date) AS month_key,
               COUNT(*) AS cnt
        $fromJoin
        GROUP BY month_key
        ORDER BY month_key ASC
        ''', args);
      final List<KpiBarSparklinePoint> callsByMonth = monthRows
          .map((row) {
            final monthKey = row['month_key'] as String? ?? '';
            final count = (row['cnt'] as num?)?.toDouble() ?? 0.0;
            return KpiBarSparklinePoint(
              value: count,
              tooltip: formatKpiMonthCallsTooltip(monthKey, count),
            );
          })
          .toList(growable: false);

      final weekdayRows = await db.rawQuery('''
        SELECT CAST(strftime('%w', calls.date) AS INTEGER) AS dow,
               COALESCE(SUM(calls.duration), 0) AS sum_dur
        $fromJoin
        AND CAST(strftime('%w', calls.date) AS INTEGER) BETWEEN 1 AND 5
        GROUP BY dow
        ORDER BY dow ASC
        ''', args);
      final weekdayDurationMap = <int, double>{
        for (final row in weekdayRows)
          (row['dow'] as num?)?.toInt() ?? 0:
              (row['sum_dur'] as num?)?.toDouble() ?? 0.0,
      };
      final durationByWeekdayMonToFri = List<KpiBarSparklinePoint>.generate(
        5,
        (index) => kpiWeekdayDurationPoint(
          index,
          weekdayDurationMap[index + 1] ?? 0.0,
        ),
      );

      final longestDurRows = await db.rawQuery('''
        SELECT COALESCE(calls.duration, 0) AS dur
        $fromJoin
        ORDER BY dur DESC
        LIMIT 3
        ''', args);
      final shortestDurRows = await db.rawQuery('''
        SELECT COALESCE(calls.duration, 0) AS dur
        $fromJoin
        AND COALESCE(calls.duration, 0) > 0
        ORDER BY dur ASC
        LIMIT 3
        ''', args);
      final List<KpiBarSparklinePoint> durationExtremesSix =
          padBarSparklinePoints([
            ...longestDurRows.asMap().entries.map(
              (entry) => kpiDurationExtremePoint(
                entry.key,
                (entry.value['dur'] as num?)?.toDouble() ?? 0,
              ),
            ),
            ...shortestDurRows.asMap().entries.map(
              (entry) => kpiDurationExtremePoint(
                entry.key + 3,
                (entry.value['dur'] as num?)?.toDouble() ?? 0,
              ),
            ),
          ], 6);

      allDatesBarSparklines = KpiAllDatesBarSparklines(
        callsByMonth: callsByMonth.isEmpty
            ? const [KpiBarSparklinePoint(value: 0, tooltip: '')]
            : callsByMonth,
        durationByWeekdayMonToFri: durationByWeekdayMonToFri,
        durationExtremesSix: durationExtremesSix,
        departmentCountsRank2To6: runnerUpPointsFromDepartmentStats(
          byDepartment,
          5,
        ),
        callerCountsRank2To6: runnerUpPointsFromCallerStats(topCallers, 5),
        issueCountsRank2To6: runnerUpPointsFromIssueStats(byIssue, 5),
      );
    }

    return DashboardSummaryModel(
      totalCalls: totalCalls,
      totalDurationSeconds: totalDurationSeconds,
      avgDurationSeconds: avgDurationSeconds,
      previousPeriodTotalCalls: previousPeriodTotalCalls,
      previousPeriodTotalDurationSeconds: previousPeriodTotalDurationSeconds,
      previousPeriodAvgDurationSeconds: previousPeriodAvgDurationSeconds,
      isAllDatesMode: isAllDatesMode,
      totalActiveDays: totalActiveDays,
      medianDurationSeconds: medianDurationSeconds,
      historyDateFrom: historyDateFrom,
      historyDateTo: historyDateTo,
      allDatesBarSparklines: allDatesBarSparklines,
      dailyTrend: dailyTrend,
      sparklineLast7Days: sparklineLast7Days,
      topCallers: topCallers,
      longestCalls: longestCalls,
      hourlyDistribution: hourlyDistribution,
      byDepartment: byDepartment,
      byIssue: byIssue,
    );
  }

  /// Κλήσεις για αναφορά dashboard (Lansweeper) με τα ίδια φίλτρα των KPIs.
  Future<List<CallModel>> getDashboardCalls(DashboardFilterModel filter) async {
    const userPhoneExpr =
        "COALESCE(NULLIF(TRIM(calls.phone_text), ''), upl.phone_list, '-')";
    const deptExpr = "COALESCE(departments.name, calls.department_text, '-')";
    const equipExpr =
        "COALESCE(equipment.code_equipment, calls.equipment_text, '')";
    const callerNameExpr =
        "TRIM(COALESCE(users.first_name, '') || ' ' || COALESCE(users.last_name, ''))";
    const callerLabelExpr =
        "CASE WHEN TRIM($callerNameExpr) = '' "
        "THEN COALESCE(NULLIF(TRIM(calls.caller_text), ''), '-') "
        "ELSE TRIM($callerNameExpr) END";

    final whereClauses = <String>['COALESCE(calls.is_deleted, 0) = 0'];
    final args = <dynamic>[];

    final dept = filter.department?.trim();
    if (dept != null && dept.isNotEmpty) {
      whereClauses.add('$deptExpr = ?');
      args.add(dept);
    }

    final userQ = filter.userName?.trim();
    if (userQ != null && userQ.isNotEmpty) {
      _appendDashboardUserFilter(whereClauses, args, userPhoneExpr, userQ);
    }

    final eqQ = filter.equipmentCode?.trim();
    if (eqQ != null && eqQ.isNotEmpty) {
      whereClauses.add('$equipExpr LIKE ?');
      args.add('%$eqQ%');
    }

    final kw = filter.keyword.trim();
    if (kw.isNotEmpty) {
      final nk = SearchTextNormalizer.normalizeForSearch(kw);
      if (nk.isNotEmpty) {
        whereClauses.add('calls.search_index LIKE ?');
        args.add('%$nk%');
      }
    }

    final df = filter.dateFromSql;
    final dt = filter.dateToSql;
    if (df != null && df.isNotEmpty) {
      whereClauses.add('calls.date >= ?');
      args.add(df);
    }
    if (dt != null && dt.isNotEmpty) {
      whereClauses.add('calls.date <= ?');
      args.add(dt);
    }

    final rows = await db.rawQuery('''
      SELECT
        calls.id,
        calls.date,
        calls.time,
        calls.caller_id,
        calls.equipment_id,
        $callerLabelExpr AS caller_text,
        calls.phone_text,
        calls.department_text,
        calls.equipment_text,
        calls.issue,
        calls.category_text,
        calls.category_id,
        calls.status,
        calls.duration,
        calls.is_priority,
        calls.lansweeper_state,
        calls.lansweeper_main_ticket_id,
        calls.lansweeper_last_sync_at,
        calls.is_deleted
      FROM calls
      LEFT JOIN users ON calls.caller_id = users.id
      LEFT JOIN (
        SELECT up.user_id AS uid,
               GROUP_CONCAT(p.number, ', ') AS phone_list
        FROM user_phones up
        JOIN phones p ON p.id = up.phone_id
        GROUP BY up.user_id
      ) upl ON upl.uid = users.id
      LEFT JOIN equipment ON calls.equipment_id = equipment.id
      LEFT JOIN departments ON users.department_id = departments.id
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY calls.date DESC, calls.time DESC, calls.id DESC
      ''', args);

    return rows.map(CallModel.fromMap).toList();
  }
}
