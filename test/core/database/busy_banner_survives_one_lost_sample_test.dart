// Ένα μεμονωμένο δείγμα «δεν απαντά» δεν επιτρέπεται να σβήσει την κίτρινη.
//
//   flutter test test/core/database/busy_banner_survives_one_lost_sample_test.dart

import 'package:call_logger/core/database/database_reachability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 9, 24, 20, 49, 14);

  group('η κίτρινη λωρίδα μέσα στο κλείδωμα', () {
    test('ΕΝΑ δείγμα «δεν απαντά» δεν τη σβήνει', () {
      // Το σενάριο της 24/09: σε κλείδωμα 75 δευτερολέπτων η λωρίδα άναψε στις
      // 20:49:14, έλειπε στο στιγμιότυπο των 20:49:19 και επανήλθε στις
      // 20:49:24. Μέσα σε κλείδωμα ο έλεγχος του αρχείου χτυπά συχνά το όριο
      // χρόνου του, οπότε ένα «δεν απαντά» δεν είναι είδηση — είναι θόρυβος.
      final tracker = DatabaseReachabilityTracker()..recordRealStall(t0);
      expect(tracker.state, DatabaseReachability.busy);

      final after = tracker.recordSample(
        DatabaseProbeSample.unreachable,
        now: t0.add(const Duration(seconds: 5)),
      );

      expect(
        after,
        DatabaseReachability.busy,
        reason:
            'Ένα δείγμα δεν αποδεικνύει χαμένο φάκελο· χρειάζονται δύο. Ως '
            'τότε η κατάσταση παραμένει «απασχολημένη», όχι «όλα εντάξει».',
      );
    });

    test('ΕΝΑ δείγμα «νεκρή σύνδεση» δεν τη σβήνει', () {
      final tracker = DatabaseReachabilityTracker()..recordRealStall(t0);

      final after = tracker.recordSample(
        DatabaseProbeSample.staleConnection,
        now: t0.add(const Duration(seconds: 5)),
      );

      expect(after, isNot(DatabaseReachability.ok));
    });

    test('ΕΝΑ δείγμα «κλειδωμένη» δεν σβήνει την ΚΟΚΚΙΝΗ', () {
      // Ο χαμένος φάκελος είναι η βαρύτερη είδηση· δεν υποβαθμίζεται σε «όλα
      // εντάξει» επειδή ένα δείγμα πρόλαβε να δει κλείδωμα.
      final tracker = DatabaseReachabilityTracker()
        ..recordSample(DatabaseProbeSample.unreachable, now: t0)
        ..recordSample(DatabaseProbeSample.unreachable, now: t0);
      expect(tracker.state, DatabaseReachability.lost);

      final after = tracker.recordSample(
        DatabaseProbeSample.locked,
        now: t0.add(const Duration(seconds: 5)),
      );

      expect(after, isNot(DatabaseReachability.ok));
    });

    test('ΔΥΟ δείγματα «δεν απαντά» εξακολουθούν να λένε «χάθηκε»', () {
      // Ο φρουρός δεν χαλαρώνει: η βαρύτερη είδηση παίρνει το τιμόνι μόλις
      // επιβεβαιωθεί.
      final tracker = DatabaseReachabilityTracker()
        ..recordRealStall(t0)
        ..recordSample(DatabaseProbeSample.unreachable, now: t0)
        ..recordSample(DatabaseProbeSample.unreachable, now: t0);

      expect(tracker.state, DatabaseReachability.lost);
    });
  });
}
