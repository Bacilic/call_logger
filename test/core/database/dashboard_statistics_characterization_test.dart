// Φωτογραφία ΟΛΟΚΛΗΡΟΥ του αποτελέσματος των στατιστικών, πάνω σε στημένα
// δεδομένα.
//
// Ο υπολογισμός παράγει δεκαέξι ενότητες από δεκαέξι χωριστά ερωτήματα. Όσο
// ζούσαν σε μία μέθοδο, κανείς δεν μπορούσε να αγγίξει τη μία χωρίς να ρισκάρει
// τις άλλες δεκαπέντε — και τα τεστ που υπήρχαν φύλαγαν μόνο δύο από αυτές.
//
// Αυτό το αρχείο δεν κρίνει αν τα νούμερα είναι **σωστά**: κρίνει αν είναι
// **ίδια**. Είναι το δίχτυ κάτω από τη διάσπαση, και μένει μετά — γιατί η ίδια
// ερώτηση («άλλαξε κάτι χωρίς να το θέλουμε;») θα ξαναχρειαστεί.
//
//   flutter test test/core/database/dashboard_statistics_characterization_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_dashboard_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late CallsRepository calls;
  late CallsDashboardRepository dashboard;
  late Database db;

  setUpAll(() async {
    // Οι ετικέτες των γραφημάτων γράφουν μήνες στα ελληνικά.
    await initializeDateFormatting('el');
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('dashboard_char_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/dashboard_char.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('calls');
    resetTestOperator();
    calls = CallsRepository(db);
    dashboard = CallsDashboardRepository(db);
  });

  tearDown(resetTestOperator);

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  // Σταθερές ημερομηνίες: το αποτέλεσμα δεν επιτρέπεται να αλλάζει επειδή
  // άλλαξε η μέρα που τρέχει το τεστ. Δύο μήνες (Μάρτιος, Απρίλιος 2026), τρεις
  // καλούντες, τρία τμήματα, πέντε διαφορετικές διάρκειες και ώρες.
  Future<void> seed() async {
    Future<void> add({
      required String caller,
      required String department,
      required String issue,
      required String date,
      required String time,
      required int duration,
    }) async {
      await calls.insertCall(
        CallModel(
          callerText: caller,
          departmentText: department,
          category: 'Medico',
          issue: issue,
          status: 'completed',
          duration: duration,
          date: date,
          time: time,
        ),
      );
    }

    await add(
      caller: 'Βαρβάρα Ψαρρά',
      department: 'Αιματολογικό',
      issue: 'Δεν ανοίγει',
      date: '2026-03-02',
      time: '09:15',
      duration: 300,
    );
    await add(
      caller: 'Βαρβάρα Ψαρρά',
      department: 'Αιματολογικό',
      issue: 'Δεν ανοίγει',
      date: '2026-03-02',
      time: '11:40',
      duration: 120,
    );
    await add(
      caller: 'Γεωργία Παπαγεωργίου',
      department: 'Γραφείο Κίνησης',
      issue: 'Αργεί',
      date: '2026-03-03',
      time: '14:05',
      duration: 900,
    );
    await add(
      caller: 'Σοφία Δήμου',
      department: 'Γραφείο Κίνησης',
      issue: 'Δεν τυπώνει',
      date: '2026-04-10',
      time: '09:50',
      duration: 60,
    );
    await add(
      caller: 'Σοφία Δήμου',
      department: 'Μικροβιολογικό',
      issue: 'Αργεί',
      date: '2026-04-13',
      time: '16:20',
      duration: 1800,
    );
  }

  const allDates = DashboardFilterModel();

  test('ΦΩΤΟΓΡΑΦΙΑ — τα σύνολα, οι μέσοι όροι και το εύρος', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(allDates);

    expect(s.totalCalls, 5);
    expect(s.totalDurationSeconds, 3180);
    expect(s.avgDurationSeconds, 636.0);
    expect(s.medianDurationSeconds, 300);
    expect(s.totalActiveDays, 4);
    expect(s.isAllDatesMode, isTrue);
    expect(s.historyDateFrom, DateTime(2026, 3, 2));
    expect(s.historyDateTo, DateTime(2026, 4, 13));
  });

  // Ισοπαλία στο πλήθος: το τμήμα με τον ΜΕΓΑΛΥΤΕΡΟ χρόνο προηγείται.
  test('ΦΩΤΟΓΡΑΦΙΑ — η κατανομή ανά τμήμα', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(allDates);

    expect(s.byDepartment.map((d) => d.name).toList(), [
      'Γραφείο Κίνησης',
      'Αιματολογικό',
      'Μικροβιολογικό',
    ]);
    expect(s.byDepartment.map((d) => d.count).toList(), [2, 2, 1]);
    expect(s.byDepartment.map((d) => d.sumDurationSeconds).toList(), [
      960,
      420,
      1800,
    ]);
  });

  // Το πεδίο λέγεται «byCategory» αλλά ομαδοποιεί κατά ΚΑΤΗΓΟΡΙΑ — η κάρτα που το
  // δείχνει τιτλοφορείται σωστά «Κατανομή ανά κατηγορία». Εδώ φυλάσσεται η
  // σημερινή συμπεριφορά, όχι το όνομα.
  test('ΦΩΤΟΓΡΑΦΙΑ — η κατανομή ομαδοποιεί κατά κατηγορία', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(allDates);

    expect(s.byCategory.map((i) => i.name).toList(), ['Medico']);
    expect(s.byCategory.single.count, 5);
    expect(s.byCategory.single.sumDurationSeconds, 3180);
  });

  test('ΦΩΤΟΓΡΑΦΙΑ — οι κορυφαίοι καλούντες και τα σύνολα χρόνου', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(allDates);

    expect(s.topCallers.map((c) => c.name).toList(), [
      'Βαρβάρα Ψαρρά',
      'Σοφία Δήμου',
      'Γεωργία Παπαγεωργίου',
    ]);
    expect(s.topCallers.map((c) => c.count).toList(), [2, 2, 1]);

    // Άλλη κατάταξη από τους «κορυφαίους»: εδώ ζυγίζει ο χρόνος, όχι το πλήθος.
    expect(s.callerTimeTotals.map((c) => c.name).toList(), [
      'Σοφία Δήμου',
      'Γεωργία Παπαγεωργίου',
      'Βαρβάρα Ψαρρά',
    ]);
    expect(s.callerTimeTotals.map((c) => c.totalDurationSeconds).toList(), [
      1860,
      900,
      420,
    ]);
    expect(s.callerTimeTotals.map((c) => c.callCount).toList(), [2, 1, 2]);
  });

  test('ΦΩΤΟΓΡΑΦΙΑ — οι μεγαλύτερες κλήσεις', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(allDates);

    expect(s.longestCalls.map((c) => c.durationSeconds).toList(), [
      1800,
      900,
      300,
      120,
      60,
    ]);
    expect(s.longestCalls.first.callerName, 'Σοφία Δήμου');
    expect(s.longestCalls.first.department, 'Μικροβιολογικό');
  });

  test('ΦΩΤΟΓΡΑΦΙΑ — η κατανομή ανά ώρα κρατά και τις 24', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(allDates);

    expect(s.hourlyDistribution.length, 24);
    final byHour = {for (final h in s.hourlyDistribution) h.hour: h.callCount};
    expect(byHour[9], 2);
    expect(byHour[11], 1);
    expect(byHour[14], 1);
    expect(byHour[16], 1);
    expect(byHour[0], 0);
  });

  // Η ημερήσια τάση είναι ΠΑΝΤΑ οι τελευταίες εφτά μέρες από σήμερα — όχι το
  // εύρος των δεδομένων. Με ιστορικά δεδομένα βγαίνει εφτά μηδενικά.
  test(
    'ΦΩΤΟΓΡΑΦΙΑ — η ημερήσια τάση κοιτά τις τελευταίες εφτά μέρες',
    () async {
      await seed();
      final s = await dashboard.getDashboardStatistics(allDates);

      expect(s.dailyTrend.length, 7);
      expect(s.sparklineLast7Days.length, 7);
      expect(s.dailyTrend.map((t) => t.callCount).toList(), [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
    },
  );

  test('ΦΩΤΟΓΡΑΦΙΑ — οι στήλες των καρτών KPI', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(allDates);
    final bars = s.allDatesBarSparklines;

    expect(bars, isNotNull);
    expect(bars!.callsByMonth.map((p) => p.value).toList(), [3.0, 2.0]);
    expect(bars.callsByMonth.map((p) => p.tooltip).toList(), [
      'Μαρτίου 2026: 3 κλήσεις',
      'Απριλίου 2026: 2 κλήσεις',
    ]);

    expect(bars.durationByWeekdayMonToFri.map((p) => p.value).toList(), [
      2220.0,
      900.0,
      0.0,
      0.0,
      60.0,
    ]);

    // Τρεις μεγαλύτερες, μετά τρεις μικρότερες — γι' αυτό το 300 εμφανίζεται
    // δύο φορές όταν οι κλήσεις είναι μόλις πέντε.
    expect(bars.durationExtremesSix.map((p) => p.value).toList(), [
      1800.0,
      900.0,
      300.0,
      60.0,
      120.0,
      300.0,
    ]);

    // Οι «από τη 2η θέση και κάτω» γεμίζουν με μηδενικά ως τα πέντε.
    expect(bars.departmentCountsRank2To6.map((p) => p.value).toList(), [
      2.0,
      1.0,
      0.0,
      0.0,
      0.0,
    ]);
    expect(
      bars.departmentCountsRank2To6.first.tooltip,
      '2ο · Αιματολογικό: 2 κλήσεις',
    );
    expect(bars.callerCountsRank2To6.map((p) => p.value).toList(), [
      2.0,
      1.0,
      0.0,
      0.0,
      0.0,
    ]);
    // Μία μόνο κατηγορία: δεν υπάρχει δεύτερη θέση να δείξει.
    expect(bars.categoryCountsRank2To6.map((p) => p.value).toList(), [
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
    ]);
  });

  test('ΦΩΤΟΓΡΑΦΙΑ — το φίλτρο ημερομηνίας κόβει τα ίδια παντού', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(
      DashboardFilterModel(
        dateFrom: DateTime(2026, 4, 1),
        dateTo: DateTime(2026, 4, 30),
      ),
    );

    expect(s.totalCalls, 2);
    expect(s.totalDurationSeconds, 1860);
    expect(s.isAllDatesMode, isFalse);
    expect(s.byDepartment.map((d) => d.name).toList(), [
      'Μικροβιολογικό',
      'Γραφείο Κίνησης',
    ]);
    expect(s.topCallers.single.name, 'Σοφία Δήμου');
    expect(s.topCallers.single.count, 2);

    // Με φίλτρο ημερομηνίας δεν υπάρχουν στήλες KPI — αυτές ζουν μόνο στο
    // «όλες οι ημερομηνίες».
    expect(s.allDatesBarSparklines, isNull);
  });

  // Η προηγούμενη περίοδος είναι το ίδιο μήκος, αμέσως πριν: 1–30 Απριλίου
  // συγκρίνεται με 2–31 Μαρτίου, όπου κάθονται και οι τρεις κλήσεις του Μαρτίου.
  test('ΦΩΤΟΓΡΑΦΙΑ — η προηγούμενη περίοδος', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(
      DashboardFilterModel(
        dateFrom: DateTime(2026, 4, 1),
        dateTo: DateTime(2026, 4, 30),
      ),
    );

    expect(s.previousPeriodTotalCalls, 3);
    expect(s.previousPeriodTotalDurationSeconds, 1320);
  });

  // Με φίλτρο ημερομηνίας το παράθυρο αγκυρώνεται στο «έως», οπότε δεν
  // εξαρτάται από τη μέρα που τρέχει το τεστ. Οι δύο λίστες βγαίνουν από
  // **ίδιο** παράθυρο και οφείλουν να συμφωνούν πάντα.
  test('ΦΩΤΟΓΡΑΦΙΑ — τάση και γραμμή εφτά ημερών λένε το ίδιο', () async {
    await seed();
    final s = await dashboard.getDashboardStatistics(
      DashboardFilterModel(
        dateFrom: DateTime(2026, 4, 1),
        dateTo: DateTime(2026, 4, 13),
      ),
    );

    expect(s.dailyTrend.map((t) => t.callCount).toList(), [
      0,
      0,
      0,
      1,
      0,
      0,
      1,
    ]);
    expect(s.dailyTrend.map((t) => t.totalDurationSeconds).toList(), [
      0,
      0,
      0,
      60,
      0,
      0,
      1800,
    ]);
    expect(s.dailyTrend.first.date, DateTime(2026, 4, 7));
    expect(s.dailyTrend.last.date, DateTime(2026, 4, 13));

    for (var i = 0; i < 7; i++) {
      expect(s.sparklineLast7Days[i].date, s.dailyTrend[i].date);
      expect(s.sparklineLast7Days[i].callCount, s.dailyTrend[i].callCount);
      expect(
        s.sparklineLast7Days[i].totalDurationSeconds,
        s.dailyTrend[i].totalDurationSeconds,
      );
    }
  });

  test('ΦΩΤΟΓΡΑΦΙΑ — χωρίς καμία κλήση δεν σκάει τίποτα', () async {
    final s = await dashboard.getDashboardStatistics(allDates);

    expect(s.totalCalls, 0);
    expect(s.totalDurationSeconds, 0);
    expect(s.totalActiveDays, 0);
    expect(s.byDepartment, isEmpty);
    expect(s.byCategory, isEmpty);
    expect(s.topCallers, isEmpty);
    expect(s.longestCalls, isEmpty);
    // Οι δύο σταθερού μήκους μένουν γεμάτες με μηδενικά, όχι άδειες.
    expect(s.dailyTrend.length, 7);
    expect(s.hourlyDistribution.length, 24);
  });
}
