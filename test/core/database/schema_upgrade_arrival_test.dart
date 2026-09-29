import 'package:call_logger/core/database/schema_upgrade_station_guard.dart';
import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:flutter_test/flutter_test.dart';

/// Πότε θα δει ο συνάδελφος το σημείωμα — και πότε δεν επιτρέπεται να το
/// υποσχεθούμε.
void main() {
  SessionLivenessMark mark({required DateTime lastSeen, bool listens = true}) =>
      SessionLivenessMark(
        station: 'PC922',
        version: '0.58.0',
        startedAt: lastSeen.subtract(const Duration(hours: 2)),
        lastSeen: lastSeen,
        listensForShutdownRequests: listens,
      );

  test('η αναμονή είναι ό,τι απομένει ως τον επόμενο παλμό', () {
    final wait = shutdownRequestArrivalIn(
      mark(lastSeen: DateTime(2026, 9, 28, 10, 0, 0)),
      now: DateTime(2026, 9, 28, 10, 0, 17),
    );

    expect(wait, const Duration(seconds: 43));
  });

  test('εκτέλεση που δεν ακούει δεν παίρνει αντίστροφη μέτρηση', () {
    final wait = shutdownRequestArrivalIn(
      mark(lastSeen: DateTime(2026, 9, 28, 10), listens: false),
      now: DateTime(2026, 9, 28, 10, 0, 17),
    );

    expect(wait, isNull);
  });

  test('ίχνος που ξεπέρασε τον παλμό του δεν δίνει πρόβλεψη', () {
    // Ο παλμός που περιμέναμε πέρασε χωρίς να ανανεωθεί το ίχνος: κάτι δεν πάει
    // καλά εκεί, και μια ένδειξη «όπου να ΄ναι» θα ήταν εικασία.
    final wait = shutdownRequestArrivalIn(
      mark(lastSeen: DateTime(2026, 9, 28, 10)),
      now: DateTime(2026, 9, 28, 10, 1, 5),
    );

    expect(wait, isNull);
  });

  group('μορφοποίηση', () {
    test('δείχνει λεπτά και δευτερόλεπτα', () {
      expect(
        formatShutdownRequestArrival(const Duration(seconds: 43)),
        'σε 0:43',
      );
      expect(
        formatShutdownRequestArrival(const Duration(seconds: 65)),
        'σε 1:05',
      );
    });

    test('κάτω από ένα δευτερόλεπτο δεν προσποιείται ακρίβεια', () {
      expect(formatShutdownRequestArrival(Duration.zero), 'όπου να ΄ναι');
    });
  });

  group('συμβατότητα ίχνους', () {
    test('ίχνος παλαιότερης έκδοσης διαβάζεται ως «δεν ακούω»', () {
      final decoded = SessionLivenessMark.decode(
        '{"station":"PC922","version":"0.50.0",'
        '"startedAt":"2026-09-28T08:00:00.000",'
        '"lastSeen":"2026-09-28T10:00:00.000"}',
      );

      expect(decoded, isNotNull);
      expect(decoded!.listensForShutdownRequests, isFalse);
    });

    test('η δήλωση επιβιώνει της κωδικοποίησης', () {
      final original = mark(lastSeen: DateTime(2026, 9, 28, 10));
      final round = SessionLivenessMark.decode(original.encode());

      expect(round!.listensForShutdownRequests, isTrue);
    });

    test('το σημάδι ζωής κρατά τη δήλωση όταν ανανεώνεται', () {
      final refreshed = mark(
        lastSeen: DateTime(2026, 9, 28, 10),
      ).seenAt(DateTime(2026, 9, 28, 10, 1));

      expect(refreshed.listensForShutdownRequests, isTrue);
      expect(refreshed.lastSeen, DateTime(2026, 9, 28, 10, 1));
    });
  });
}
