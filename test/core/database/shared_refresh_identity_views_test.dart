import 'package:call_logger/core/database/shared_database_refresh.dart';
import 'package:call_logger/features/database/providers/active_sessions_provider.dart';
import 'package:call_logger/features/database/providers/database_browser_stats_provider.dart';
import 'package:call_logger/features/database/services/active_sessions.dart';
import 'package:call_logger/features/database/models/database_stats.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Όταν γράψει άλλος υπολογιστής, ξαναρωτιούνται **και τα δύο**: ποιος είναι
/// μέσα, και τι λέει η βάση για τον εαυτό της.
///
/// **Το σενάριο πεδίου (28/09):** ο PICINIO αναβάθμισε τη βάση σε σχήμα 67. Η
/// ανοιχτή οθόνη του POPINIO συνέχισε να δείχνει 66 επ' αόριστον, και η λίστα
/// «Ανοιχτή τώρα από» έμεινε κι εκείνη παγωμένη — οπότε ούτε η προειδοποίηση
/// «δεν θα μπορεί να ξανανοίξει τη βάση» θα εμφανιζόταν ποτέ.
/// Εκθέτει έναν πραγματικό [Ref] στο τεστ: ο κύκλος ανανέωσης δέχεται αυτόν,
/// όχι τον container, γιατί στην εφαρμογή τρέχει μέσα από provider.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  /// Μετρά πόσες φορές ξαναχτίστηκε ο κάθε provider.
  ({int sessions, int stats}) buildCounts(List<int> s, List<int> t) =>
      (sessions: s.length, stats: t.length);

  late List<int> sessionBuilds;
  late List<int> statBuilds;
  late ProviderContainer container;

  setUp(() {
    sessionBuilds = [];
    statBuilds = [];
    resetSharedDatabaseStatsThrottle();
    container = ProviderContainer(
      overrides: [
        activeSessionsProvider.overrideWith((ref) async {
          sessionBuilds.add(1);
          // Κρατιέται ζωντανός: ο `autoDispose` θα τον έσβηνε μόλις τελειώσει
          // η ανάγνωση, και το τεστ δεν θα μετρούσε ποτέ δεύτερο χτίσιμο.
          ref.keepAlive();
          return const <ActiveSession>[];
        }),
        databaseBrowserStatsProvider.overrideWith((ref) async {
          statBuilds.add(1);
          ref.keepAlive();
          return const DatabaseStats(
            fileSizeBytes: 0,
            dbPath: 'x.db',
            rowCountsByTable: {},
          );
        }),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    resetSharedDatabaseStatsThrottle();
  });

  Future<void> warmUp() async {
    await container.read(activeSessionsProvider.future);
    await container.read(databaseBrowserStatsProvider.future);
  }

  test('η ξένη εγγραφή ξαναρωτά και τις δύο όψεις', () async {
    await warmUp();
    expect(buildCounts(sessionBuilds, statBuilds), (sessions: 1, stats: 1));

    refreshSharedDatabaseIdentityViews(container.read(_refProvider));
    await warmUp();

    expect(buildCounts(sessionBuilds, statBuilds), (sessions: 2, stats: 2));
  });

  test(
    'ο πυκνός κύκλος ξαναρωτά τις συνεδρίες ΑΛΛΑ όχι τα ακριβά στατιστικά',
    () async {
      await warmUp();

      // Πέντε χτύποι του κύκλου μέσα στο ίδιο λεπτό.
      for (var i = 0; i < 5; i++) {
        refreshSharedDatabaseIdentityViews(container.read(_refProvider));
        await warmUp();
      }

      // Οι συνεδρίες είναι φθηνές και κρίνουν απόφαση: κάθε φορά.
      expect(sessionBuilds.length, 6);
      // Τα στατιστικά μετρούν κάθε πίνακα: μία φορά μόνο.
      expect(statBuilds.length, 2);
    },
  );

  test('ο μηδενισμός επιτρέπει αμέσως νέα μέτρηση', () async {
    await warmUp();
    refreshSharedDatabaseIdentityViews(container.read(_refProvider));
    await warmUp();
    expect(statBuilds.length, 2);

    refreshSharedDatabaseIdentityViews(container.read(_refProvider));
    await warmUp();
    expect(statBuilds.length, 2, reason: 'φραγμένο μέσα στο λεπτό');

    // Άλλαξε η βάση.
    resetSharedDatabaseStatsThrottle();
    refreshSharedDatabaseIdentityViews(container.read(_refProvider));
    await warmUp();

    expect(statBuilds.length, 3);
  });
}
