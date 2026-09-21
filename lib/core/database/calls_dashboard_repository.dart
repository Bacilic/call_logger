import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/calls/models/call_model.dart';
import '../../features/history/models/dashboard_filter_model.dart';
import '../../features/history/models/dashboard_summary_model.dart';
import '../utils/search_text_normalizer.dart';
import 'call_entity_filters.dart';

/// Στατιστικά και λίστες κλήσεων για τον πίνακα ελέγχου (μόνο αναγνώσεις).
class CallsDashboardRepository {
  const CallsDashboardRepository(this.db);

  final Database db;

  /// Στατιστικά κλήσεων για πίνακα ελέγχου: KPIs, ανά τμήμα, ανά κατηγορία.
  ///
  /// Η μέθοδος **συναρμολογεί**· δεν υπολογίζει. Κάθε ενότητα του πίνακα έχει
  /// δικό της ερώτημα και δική της μέθοδο παρακάτω, ώστε να αλλάζει μία χωρίς
  /// να διαβαστούν οι υπόλοιπες. Όλες μοιράζονται το ίδιο [_DashboardScope] —
  /// το φίλτρο χτίζεται **μία** φορά και δεν μπορεί να αποκλίνει μεταξύ τους.
  Future<DashboardSummaryModel> getDashboardStatistics(
    DashboardFilterModel filter,
  ) async {
    final scope = _scopeFor(filter);

    final kpi = await _readKpiTotals(scope);
    final previousKpi = await _readPreviousKpiTotals(scope, filter);
    final byDepartment = await _readDepartmentStats(scope);
    final byCategory = await _readCategoryStats(scope);
    final topCallers = await _readTopCallers(scope);
    final longestCalls = await _readLongestCalls(scope);
    final callerTimeTotals = await _readCallerTimeTotals(scope);
    final hourlyDistribution = await _readHourlyDistribution(scope);

    // Η «τάση» και η «γραμμή εφτά ημερών» είναι το ΙΔΙΟ παράθυρο, αγκυρωμένο
    // στην ίδια μέρα. Ως τις 19/09/2026 υπολογίζονταν με δύο χωριστά ερωτήματα
    // που έδιναν πάντα ταυτόσημο αποτέλεσμα — τώρα ρωτιέται μία φορά.
    final sevenDayTrend = await _readSevenDayTrend(scope);

    final extras = await _readAllDatesExtras(
      scope,
      totalCalls: kpi.count,
      byDepartment: byDepartment,
      topCallers: topCallers,
      byCategory: byCategory,
    );

    return DashboardSummaryModel(
      totalCalls: kpi.count,
      totalDurationSeconds: kpi.durationSeconds,
      avgDurationSeconds: kpi.avgDurationSeconds,
      previousPeriodTotalCalls: previousKpi.count,
      previousPeriodTotalDurationSeconds: previousKpi.durationSeconds,
      previousPeriodAvgDurationSeconds: previousKpi.avgDurationSeconds,
      isAllDatesMode: scope.isAllDatesMode,
      totalActiveDays: extras.activeDays,
      medianDurationSeconds: extras.medianDurationSeconds,
      historyDateFrom: extras.historyDateFrom,
      historyDateTo: extras.historyDateTo,
      allDatesBarSparklines: extras.bars,
      dailyTrend: sevenDayTrend,
      sparklineLast7Days: sevenDayTrend,
      topCallers: topCallers,
      longestCalls: longestCalls,
      callerTimeTotals: callerTimeTotals,
      hourlyDistribution: hourlyDistribution,
      byDepartment: byDepartment,
      byCategory: byCategory,
    );
  }

  // ── Το κοινό φίλτρο ─────────────────────────────────────────────────────────

  /// Χτίζει **μία** φορά ό,τι μοιράζονται όλα τα ερωτήματα του πίνακα.
  _DashboardScope _scopeFor(DashboardFilterModel filter) {
    final baseWhere = <String>['COALESCE(calls.is_deleted, 0) = 0'];
    final baseArgs = <dynamic>[];

    appendCallEntityFilters(
      baseWhere,
      baseArgs,
      department: filter.department,
      userName: filter.userName,
      equipmentCode: filter.equipmentCode,
    );

    appendCallCategoryFilter(baseWhere, baseArgs, category: filter.category);

    final keyword = filter.keyword.trim();
    if (keyword.isNotEmpty) {
      final normalized = SearchTextNormalizer.normalizeForSearch(keyword);
      if (normalized.isNotEmpty) {
        baseWhere.add('calls.search_index LIKE ?');
        baseArgs.add('%$normalized%');
      }
    }

    final where = List<String>.from(baseWhere);
    final args = List<dynamic>.from(baseArgs);
    final from = filter.dateFromSql;
    final to = filter.dateToSql;
    final isAllDatesMode =
        (from == null || from.isEmpty) && (to == null || to.isEmpty);
    if (from != null && from.isNotEmpty) {
      where.add('calls.date >= ?');
      args.add(from);
    }
    if (to != null && to.isNotEmpty) {
      where.add('calls.date <= ?');
      args.add(to);
    }

    // Η αγκύρωση των παραθύρων: το «έως» του φίλτρου αν υπάρχει, αλλιώς σήμερα.
    // Έτσι τα εφτά ημερών κοιτούν τις μέρες που βλέπει ο χρήστης, όχι πάντα τις
    // τελευταίες του ημερολογίου.
    final now = DateTime.now();
    final anchorDate =
        filter.dateTo ??
        filter.dateFrom ??
        DateTime(now.year, now.month, now.day);

    return _DashboardScope(
      baseWhere: baseWhere,
      baseArgs: baseArgs,
      args: args,
      fromJoin: _dashboardFromJoin(where),
      isAllDatesMode: isAllDatesMode,
      anchorDay: DateTime(anchorDate.year, anchorDate.month, anchorDate.day),
    );
  }

  // ── Οι ενότητες, μία μέθοδος η καθεμία ──────────────────────────────────────

  Future<_KpiTotals> _readKpiTotals(_DashboardScope scope) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c,
             COALESCE(SUM(calls.duration), 0) AS total_dur,
             AVG(calls.duration) AS avg_dur
      ${scope.fromJoin}
      ''', scope.args);
    return _KpiTotals.fromRow(rows.isEmpty ? const {} : rows.first);
  }

  /// Η ίδια περίοδος, μετατοπισμένη πίσω — για τα βελάκια σύγκρισης.
  ///
  /// Στο «όλες οι ημερομηνίες» δεν υπάρχει προηγούμενη περίοδος να συγκριθεί,
  /// οπότε δεν γίνεται καν ερώτημα.
  Future<_KpiTotals> _readPreviousKpiTotals(
    _DashboardScope scope,
    DashboardFilterModel filter,
  ) async {
    if (scope.isAllDatesMode) return const _KpiTotals.empty();

    final where = List<String>.from(scope.baseWhere);
    final args = List<dynamic>.from(scope.baseArgs);
    final range = filter.previousComparisonRangeInclusive;
    if (range != null) {
      where.add('calls.date >= ?');
      args.add(DateFormat('yyyy-MM-dd').format(range.start));
      where.add('calls.date <= ?');
      args.add(DateFormat('yyyy-MM-dd').format(range.end));
    } else {
      where.add('calls.date = ?');
      args.add(
        DateFormat(
          'yyyy-MM-dd',
        ).format(scope.anchorDay.subtract(const Duration(days: 1))),
      );
    }

    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c,
             COALESCE(SUM(calls.duration), 0) AS total_dur,
             AVG(calls.duration) AS avg_dur
      ${_dashboardFromJoin(where)}
      ''', args);
    return _KpiTotals.fromRow(rows.isEmpty ? const {} : rows.first);
  }

  Future<List<DepartmentStat>> _readDepartmentStats(
    _DashboardScope scope,
  ) async {
    final rows = await db.rawQuery('''
      SELECT $kCallDepartmentExpr AS dept_name,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      ${scope.fromJoin}
      GROUP BY $kCallDepartmentExpr
      ORDER BY cnt DESC
      ''', scope.args);

    return rows
        .map(
          (row) => DepartmentStat(
            name: _labelOrFallback(
              row['dept_name'],
              kDashboardUnknownDepartmentLabel,
            ),
            count: (row['cnt'] as num?)?.toInt() ?? 0,
            sumDurationSeconds: (row['sum_dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  /// Η κάρτα «Κατανομή ανά κατηγορία».
  ///
  /// Ομαδοποιεί κατά **κατηγορία** — κλειστή λίστα — και όχι κατά τη βλάβη, που
  /// είναι ελεύθερο κείμενο και δεν ομαδοποιείται χρήσιμα.
  Future<List<CategoryStat>> _readCategoryStats(_DashboardScope scope) async {
    const rawExpr =
        "COALESCE(NULLIF(TRIM(cat.name), ''), NULLIF(TRIM(calls.category_text), ''))";
    final escapedNoCategory = kDashboardNoCategoryLabel.replaceAll("'", "''");
    final labelExpr =
        "CASE WHEN $rawExpr IS NULL "
        "THEN '$escapedNoCategory' "
        "ELSE $rawExpr END";

    final rows = await db.rawQuery('''
      SELECT $labelExpr AS category_label,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      ${scope.fromJoin}
      GROUP BY $labelExpr
      ORDER BY cnt DESC
      LIMIT 15
      ''', scope.args);

    return rows
        .map(
          (row) => CategoryStat(
            name: (row['category_label'] as String?)?.trim() ?? '',
            count: (row['cnt'] as num?)?.toInt() ?? 0,
            sumDurationSeconds: (row['sum_dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  /// Οι εφτά μέρες που κλείνουν στην αγκύρωση, με μηδενικά όπου δεν υπάρχει
  /// κλήση — το γράφημα θέλει και τις εφτά, αλλιώς οι μέρες μετατοπίζονται.
  Future<List<DailyTrendPoint>> _readSevenDayTrend(
    _DashboardScope scope,
  ) async {
    final start = scope.anchorDay.subtract(const Duration(days: 6));
    final where = List<String>.from(scope.baseWhere)
      ..add('calls.date >= ?')
      ..add('calls.date <= ?');
    final args = List<dynamic>.from(scope.baseArgs)
      ..add(DateFormat('yyyy-MM-dd').format(start))
      ..add(DateFormat('yyyy-MM-dd').format(scope.anchorDay));

    final rows = await db.rawQuery('''
      SELECT calls.date AS day,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS sum_dur
      ${_dashboardFromJoin(where)}
      GROUP BY calls.date
      ORDER BY calls.date ASC
      ''', args);

    final byDate = <String, Map<String, dynamic>>{
      for (final row in rows) (row['day'] as String? ?? ''): row,
    };
    return List<DailyTrendPoint>.generate(7, (index) {
      final day = start.add(Duration(days: index));
      final row = byDate[DateFormat('yyyy-MM-dd').format(day)];
      return DailyTrendPoint(
        date: day,
        callCount: (row?['cnt'] as num?)?.toInt() ?? 0,
        totalDurationSeconds: (row?['sum_dur'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<List<CallerStat>> _readTopCallers(_DashboardScope scope) async {
    final rows = await db.rawQuery('''
      SELECT $kCallCallerLabelExpr AS caller_name,
             COUNT(*) AS cnt
      ${scope.fromJoin}
      GROUP BY $kCallCallerLabelExpr
      ORDER BY cnt DESC, caller_name ASC
      LIMIT 10
      ''', scope.args);

    return rows
        .map(
          (row) => CallerStat(
            name: _labelOrFallback(
              row['caller_name'],
              kDashboardUnknownCallerLabel,
            ),
            count: (row['cnt'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  Future<List<LongestCallEntry>> _readLongestCalls(
    _DashboardScope scope,
  ) async {
    final rows = await db.rawQuery('''
      SELECT $kCallCallerLabelExpr AS caller_name,
             $kCallDepartmentExpr AS dept_name,
             COALESCE(calls.duration, 0) AS dur
      ${scope.fromJoin}
      ORDER BY dur DESC, caller_name ASC
      LIMIT 20
      ''', scope.args);

    return rows
        .map(
          (row) => LongestCallEntry(
            callerName: _labelOrFallback(row['caller_name'], '-'),
            department: _labelOrFallback(row['dept_name'], '-'),
            durationSeconds: (row['dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  /// Συγκεντρωτικός χρόνος ανά καλούντα: άλλο ερώτημα από τις μεμονωμένες
  /// κλήσεις — λίγες μεγάλες ζυγίζουν διαφορετικά από πολλές σύντομες.
  Future<List<CallerTimeStat>> _readCallerTimeTotals(
    _DashboardScope scope,
  ) async {
    final rows = await db.rawQuery('''
      SELECT $kCallCallerLabelExpr AS caller_name,
             COUNT(*) AS cnt,
             COALESCE(SUM(calls.duration), 0) AS total_dur
      ${scope.fromJoin}
      GROUP BY $kCallCallerLabelExpr
      ORDER BY total_dur DESC, caller_name ASC
      LIMIT 20
      ''', scope.args);

    return rows
        .map(
          (row) => CallerTimeStat(
            name: _labelOrFallback(
              row['caller_name'],
              kDashboardUnknownCallerLabel,
            ),
            callCount: (row['cnt'] as num?)?.toInt() ?? 0,
            totalDurationSeconds: (row['total_dur'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  /// Και οι 24 ώρες, με μηδενικά όπου δεν υπάρχει κλήση.
  Future<List<HourlyBucket>> _readHourlyDistribution(
    _DashboardScope scope,
  ) async {
    final rows = await db.rawQuery('''
      SELECT CAST(SUBSTR(COALESCE(calls.time, '00:00'), 1, 2) AS INTEGER) AS hh,
             COUNT(*) AS cnt
      ${scope.fromJoin}
      GROUP BY hh
      ORDER BY hh ASC
      ''', scope.args);

    final byHour = <int, int>{
      for (final row in rows)
        (row['hh'] as num?)?.toInt() ?? 0: (row['cnt'] as num?)?.toInt() ?? 0,
    };
    return List<HourlyBucket>.generate(
      24,
      (hour) => HourlyBucket(hour: hour, callCount: byHour[hour] ?? 0),
    );
  }

  /// Ό,τι υπάρχει **μόνο** στο «όλες οι ημερομηνίες»: εύρος ιστορικού, διάμεσος
  /// και οι στήλες των καρτών KPI.
  ///
  /// Με φίλτρο ημερομηνίας — ή χωρίς καμία κλήση — δεν γίνεται κανένα από τα
  /// έξι ερωτήματα αυτής της ενότητας.
  Future<_AllDatesExtras> _readAllDatesExtras(
    _DashboardScope scope, {
    required int totalCalls,
    required List<DepartmentStat> byDepartment,
    required List<CallerStat> topCallers,
    required List<CategoryStat> byCategory,
  }) async {
    if (!scope.isAllDatesMode || totalCalls <= 0) {
      return const _AllDatesExtras.empty();
    }

    final activeRows = await db.rawQuery('''
        SELECT COUNT(DISTINCT calls.date) AS active_days,
               MIN(calls.date) AS min_date,
               MAX(calls.date) AS max_date
        ${scope.fromJoin}
        ''', scope.args);
    final activeRow = activeRows.isEmpty ? null : activeRows.first;

    final durationRows = await db.rawQuery('''
        SELECT calls.duration AS dur
        ${scope.fromJoin}
        ORDER BY calls.duration ASC
        ''', scope.args);

    final monthRows = await db.rawQuery('''
        SELECT strftime('%Y-%m', calls.date) AS month_key,
               COUNT(*) AS cnt
        ${scope.fromJoin}
        GROUP BY month_key
        ORDER BY month_key ASC
        ''', scope.args);
    final callsByMonth = monthRows
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
        ${scope.fromJoin}
        AND CAST(strftime('%w', calls.date) AS INTEGER) BETWEEN 1 AND 5
        GROUP BY dow
        ORDER BY dow ASC
        ''', scope.args);
    final weekdayDuration = <int, double>{
      for (final row in weekdayRows)
        (row['dow'] as num?)?.toInt() ?? 0:
            (row['sum_dur'] as num?)?.toDouble() ?? 0.0,
    };

    final longestRows = await db.rawQuery('''
        SELECT COALESCE(calls.duration, 0) AS dur
        ${scope.fromJoin}
        ORDER BY dur DESC
        LIMIT 3
        ''', scope.args);
    final shortestRows = await db.rawQuery('''
        SELECT COALESCE(calls.duration, 0) AS dur
        ${scope.fromJoin}
        AND COALESCE(calls.duration, 0) > 0
        ORDER BY dur ASC
        LIMIT 3
        ''', scope.args);

    return _AllDatesExtras(
      activeDays: (activeRow?['active_days'] as num?)?.toInt() ?? 0,
      medianDurationSeconds: medianDurationSecondsFromList(
        durationRows
            .map((row) => (row['dur'] as num?)?.toInt() ?? 0)
            .toList(growable: false),
      ),
      historyDateFrom: parseDashboardSqlDate(activeRow?['min_date'] as String?),
      historyDateTo: parseDashboardSqlDate(activeRow?['max_date'] as String?),
      bars: KpiAllDatesBarSparklines(
        callsByMonth: callsByMonth.isEmpty
            ? const [KpiBarSparklinePoint(value: 0, tooltip: '')]
            : callsByMonth,
        durationByWeekdayMonToFri: List<KpiBarSparklinePoint>.generate(
          5,
          (index) =>
              kpiWeekdayDurationPoint(index, weekdayDuration[index + 1] ?? 0.0),
        ),
        durationExtremesSix: padBarSparklinePoints([
          ...longestRows.asMap().entries.map(
            (entry) => kpiDurationExtremePoint(
              entry.key,
              (entry.value['dur'] as num?)?.toDouble() ?? 0,
            ),
          ),
          ...shortestRows.asMap().entries.map(
            (entry) => kpiDurationExtremePoint(
              entry.key + 3,
              (entry.value['dur'] as num?)?.toDouble() ?? 0,
            ),
          ),
        ], 6),
        departmentCountsRank2To6: runnerUpPointsFromDepartmentStats(
          byDepartment,
          5,
        ),
        callerCountsRank2To6: runnerUpPointsFromCallerStats(topCallers, 5),
        categoryCountsRank2To6: runnerUpPointsFromCategoryStats(byCategory, 5),
      ),
    );
  }

  /// Το κείμενο της στήλης, ή η εφεδρεία όταν λείπει ή είναι η παύλα.
  static String _labelOrFallback(Object? raw, String fallback) {
    final value = (raw as String?)?.trim() ?? '';
    if (value.isEmpty || value == '-') return fallback;
    return value;
  }

  /// Κλήσεις για αναφορά dashboard (Lansweeper) με τα ίδια φίλτρα των KPIs.
  Future<List<CallModel>> getDashboardCalls(DashboardFilterModel filter) async {
    final whereClauses = <String>['COALESCE(calls.is_deleted, 0) = 0'];
    final args = <dynamic>[];

    appendCallEntityFilters(
      whereClauses,
      args,
      department: filter.department,
      userName: filter.userName,
      equipmentCode: filter.equipmentCode,
    );

    appendCallCategoryFilter(whereClauses, args, category: filter.category);

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
        $kCallCallerLabelExpr AS caller_text,
        calls.phone_text,
        calls.department_text,
        calls.equipment_text,
        calls.issue,
        calls.solution,
        calls.refined_source,
        calls.refined_at,
        calls.category_text,
        calls.category_id,
        calls.status,
        calls.duration,
        calls.is_priority,
        calls.lansweeper_state,
        calls.lansweeper_main_ticket_id,
        calls.lansweeper_last_sync_at,
        calls.created_by_operator_id,
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

/// Το κοινό `FROM … WHERE` όλων των ερωτημάτων του πίνακα ελέγχου.
///
/// Γραφόταν αυτούσιο **τέσσερις** φορές μέσα στην ίδια μέθοδο. Τέσσερα
/// αντίγραφα ενός JOIN σημαίνουν ότι μια στήλη που προστίθεται σε ένα από αυτά
/// λείπει σιωπηλά από τα άλλα τρία.
String _dashboardFromJoin(List<String> where) =>
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
WHERE ${where.join(' AND ')}
''';

/// Ό,τι μοιράζονται όλα τα ερωτήματα μιας κλήσης του πίνακα ελέγχου.
///
/// Υπάρχει για να μην μπορεί μια ενότητα να φιλτράρει διαφορετικά από τις
/// άλλες: το φίλτρο χτίζεται μία φορά και περνά αναλλοίωτο παντού.
class _DashboardScope {
  const _DashboardScope({
    required this.baseWhere,
    required this.baseArgs,
    required this.args,
    required this.fromJoin,
    required this.isAllDatesMode,
    required this.anchorDay,
  });

  /// Το φίλτρο **χωρίς** τις ημερομηνίες — βάση για τα δικά τους παράθυρα.
  final List<String> baseWhere;
  final List<dynamic> baseArgs;

  /// Οι παράμετροι που ταιριάζουν στο [fromJoin].
  final List<dynamic> args;

  /// Έτοιμο `FROM … WHERE` με τις ημερομηνίες του φίλτρου μέσα.
  final String fromJoin;

  /// Καμία ημερομηνία στο φίλτρο: τότε ζουν οι κάρτες KPI και το εύρος ιστορικού.
  final bool isAllDatesMode;

  /// Η μέρα στην οποία κλείνουν τα παράθυρα των εφτά ημερών.
  final DateTime anchorDay;
}

/// Τα τρία νούμερα μιας κάρτας KPI.
class _KpiTotals {
  const _KpiTotals({
    required this.count,
    required this.durationSeconds,
    required this.avgDurationSeconds,
  });

  const _KpiTotals.empty()
    : count = 0,
      durationSeconds = 0,
      avgDurationSeconds = 0.0;

  /// Χωρίς καμία κλήση ο μέσος όρος είναι **μηδέν**, όχι ό,τι επιστρέψει η
  /// `AVG` — που σε άδειο σύνολο δίνει `NULL`.
  factory _KpiTotals.fromRow(Map<String, dynamic> row) {
    final count = (row['c'] as num?)?.toInt() ?? 0;
    return _KpiTotals(
      count: count,
      durationSeconds: (row['total_dur'] as num?)?.toInt() ?? 0,
      avgDurationSeconds: count == 0
          ? 0.0
          : ((row['avg_dur'] as num?)?.toDouble() ?? 0.0),
    );
  }

  final int count;
  final int durationSeconds;
  final double avgDurationSeconds;
}

/// Ό,τι υπολογίζεται μόνο στο «όλες οι ημερομηνίες».
class _AllDatesExtras {
  const _AllDatesExtras({
    required this.activeDays,
    required this.medianDurationSeconds,
    required this.historyDateFrom,
    required this.historyDateTo,
    required this.bars,
  });

  const _AllDatesExtras.empty()
    : activeDays = 0,
      medianDurationSeconds = 0,
      historyDateFrom = null,
      historyDateTo = null,
      bars = null;

  final int activeDays;
  final int medianDurationSeconds;
  final DateTime? historyDateFrom;
  final DateTime? historyDateTo;
  final KpiAllDatesBarSparklines? bars;
}
