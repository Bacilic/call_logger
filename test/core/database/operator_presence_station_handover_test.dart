// Ένα ανοιχτό αντίγραφο της εφαρμογής έχει έναν χρήστη τη φορά. Μόλις αλλάξει,
// ο προηγούμενος παύει να είναι «εδώ» — δεν παλιώνει σιγά σιγά επί τρία λεπτά.
//
// Δύο ΔΙΑΦΟΡΕΤΙΚΑ αντίγραφα στον ίδιο υπολογιστή (π.χ. το κανονικό και το
// δοκιμαστικό) είναι άλλη ιστορία: εκεί δύο άνθρωποι όντως δουλεύουν μαζί.
//
//   flutter test test/core/database/operator_presence_station_handover_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/operator_presence_repository.dart';
import 'package:call_logger/core/models/operator_presence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Παράδοση σταθμού από χρήστη σε χρήστη', () {
    late Database db;
    late OperatorPresenceRepository repository;

    const station = 'PICINIO';
    const app = r'C:\Program Files\call_logger\call_logger.exe';
    const devApp = r'C:\dev\call_logger\call_logger.exe|dev';

    final at1000 = DateTime(2026, 8, 21, 10, 0);
    final at1001 = DateTime(2026, 8, 21, 10, 1);

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      // Ως την v50 χτίζεται ο πίνακας· η v52 του δίνει τη στήλη «ποιο ανοιχτό
      // αντίγραφο». Οι ενδιάμεσες αφορούν το Ιστορικό και θέλουν πίνακες που
      // αυτό το τεστ δεν έχει λόγο να στήσει.
      await onDatabaseUpgradeSquashed(db, 46, 50);
      await migrateDatabaseToV52(db);
      repository = OperatorPresenceRepository(db);
    });

    tearDown(() async => db.close());

    Future<OperatorPresence?> markFor(int operatorId) async {
      final all = await repository.getAll();
      for (final mark in all) {
        if (mark.operatorId == operatorId) return mark;
      }
      return null;
    }

    test('μετά την αλλαγή χρήστη, μόνο ο νέος είναι συνδεδεμένος', () async {
      await repository.touch(
        operatorId: 1,
        station: station,
        instance: app,
        at: at1000,
      );
      await repository.touch(
        operatorId: 2,
        station: station,
        instance: app,
        at: at1001,
      );

      final previous = await markFor(1);
      final current = await markFor(2);

      expect(
        current!.isOnlineAt(at1001),
        isTrue,
        reason: 'Ο χρήστης που μόλις ανέλαβε τον σταθμό είναι συνδεδεμένος.',
      );
      expect(
        previous!.isOnlineAt(at1001),
        isFalse,
        reason:
            'Ο προηγούμενος δεν κάθεται πια εδώ — το ίχνος του δεν επιτρέπεται '
            'να μετρά ως ζωντανό επειδή είναι απλώς φρέσκο.',
      );
    });

    test('ο προηγούμενος κρατά την τελευταία του σύνδεση', () async {
      await repository.touch(
        operatorId: 1,
        station: station,
        instance: app,
        at: at1000,
      );
      await repository.touch(
        operatorId: 2,
        station: station,
        instance: app,
        at: at1001,
      );

      final previous = await markFor(1);

      expect(previous!.lastSeenAt, at1000);
      expect(previous.station, station);
    });

    test('δύο αντίγραφα στον ίδιο υπολογιστή μετρούν και τα δύο', () async {
      await repository.touch(
        operatorId: 1,
        station: station,
        instance: app,
        at: at1000,
      );
      await repository.touch(
        operatorId: 2,
        station: station,
        instance: devApp,
        at: at1001,
      );

      expect((await markFor(1))!.isOnlineAt(at1001), isTrue);
      expect((await markFor(2))!.isOnlineAt(at1001), isTrue);
    });

    test('ο ίδιος χρήστης σε δύο σταθμούς μένει και στους δύο', () async {
      await repository.touch(
        operatorId: 1,
        station: station,
        instance: app,
        at: at1000,
      );
      await repository.touch(
        operatorId: 1,
        station: 'RADIOLOGY',
        instance: app,
        at: at1001,
      );

      final all = await repository.getAll();
      expect(all, hasLength(2));
      expect(all.every((mark) => mark.isOnlineAt(at1001)), isTrue);
    });

    test('ίχνος χωρίς ανοιχτό αντίγραφο δεν είναι ποτέ «τώρα»', () async {
      // Οι γραμμές που υπήρχαν πριν την αναβάθμιση δεν ξέρουν ποιο αντίγραφο
      // τις άφησε. Ιστορικό ναι, ζωντανή σύνδεση όχι.
      final mark = OperatorPresence(
        operatorId: 1,
        station: station,
        lastSeenAt: at1000,
        instance: null,
      );

      expect(
        mark.isOnlineAt(at1000),
        isFalse,
        reason: 'Φρέσκο ίχνος χωρίς κάτοχο είναι ιστορικό, όχι παρουσία.',
      );
    });

    test('η αναβάθμιση v52 ξανατρέχει χωρίς παρενέργειες', () async {
      await repository.touch(
        operatorId: 1,
        station: station,
        instance: app,
        at: at1000,
      );

      await migrateDatabaseToV52(db);

      final mark = await markFor(1);
      expect(mark!.instance, app);
      expect(mark.isOnlineAt(at1000), isTrue);
    });
  });
}
