import 'dart:io';

import 'package:call_logger/core/services/station_shutdown_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Το σημείωμα «κλείσε» ανάμεσα σε δύο σταθμούς: τι φτάνει, τι αγνοείται, και
/// ποιος το μαζεύει.
void main() {
  late Directory logs;

  setUp(() async {
    logs = await Directory.systemTemp.createTemp('shutdown_request_test');
  });

  tearDown(() async {
    if (await logs.exists()) await logs.delete(recursive: true);
  });

  group('ανάγνωση και γραφή', () {
    test('το σημείωμα φτάνει στον παραλήπτη που ονομάζει', () async {
      final sent = await writeShutdownRequest(
        logsDirectory: logs.path,
        toStation: 'PC922',
        toInstance: 'C:/app.exe|main',
        request: StationShutdownRequest(
          fromStation: 'PC901',
          requestedAt: DateTime(2026, 9, 28, 10),
          immediate: false,
          database: 'hospital.db',
        ),
      );
      expect(sent, isTrue);

      final got = await readShutdownRequestForMe(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'C:/app.exe|main',
        myDatabase: 'hospital.db',
        now: DateTime(2026, 9, 28, 10, 0, 30),
      );

      expect(got, isNotNull);
      expect(got!.fromStation, 'PC901');
      expect(got.immediate, isFalse);
    });

    test('ο διπλανός σταθμός δεν βλέπει ξένο σημείωμα', () async {
      await writeShutdownRequest(
        logsDirectory: logs.path,
        toStation: 'PC922',
        toInstance: 'C:/app.exe|main',
        request: StationShutdownRequest(
          fromStation: 'PC901',
          requestedAt: DateTime(2026, 9, 28, 10),
          immediate: false,
        ),
      );

      final got = await readShutdownRequestForMe(
        logsDirectory: logs.path,
        myStation: 'PC777',
        myInstance: 'C:/app.exe|main',
        now: DateTime(2026, 9, 28, 10, 0, 30),
      );

      expect(got, isNull);
    });

    test(
      'το δεύτερο αντίγραφο στον ίδιο υπολογιστή δεν παίρνει το σημείωμα του '
      'πρώτου',
      () async {
        await writeShutdownRequest(
          logsDirectory: logs.path,
          toStation: 'PC922',
          toInstance: 'C:/app.exe|main',
          request: StationShutdownRequest(
            fromStation: 'PC901',
            requestedAt: DateTime(2026, 9, 28, 10),
            immediate: false,
          ),
        );

        final got = await readShutdownRequestForMe(
          logsDirectory: logs.path,
          myStation: 'PC922',
          myInstance: 'C:/app.exe|dokimastiki',
          now: DateTime(2026, 9, 28, 10, 0, 30),
        );

        expect(got, isNull);
      },
    );
  });

  group('λήξη', () {
    test('σημείωμα παλαιότερο από 10΄ δεν κλείνει την εφαρμογή', () async {
      await writeShutdownRequest(
        logsDirectory: logs.path,
        toStation: 'PC922',
        toInstance: 'run',
        request: StationShutdownRequest(
          fromStation: 'PC901',
          requestedAt: DateTime(2026, 9, 28, 10),
          immediate: false,
        ),
      );

      final got = await readShutdownRequestForMe(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'run',
        now: DateTime(2026, 9, 28, 10, 11),
      );

      expect(got, isNull);
    });

    test('το ληγμένο σημείωμα σβήνεται, ώστε να μη ξαναρωτιέται', () async {
      await writeShutdownRequest(
        logsDirectory: logs.path,
        toStation: 'PC922',
        toInstance: 'run',
        request: StationShutdownRequest(
          fromStation: 'PC901',
          requestedAt: DateTime(2026, 9, 28, 10),
          immediate: false,
        ),
      );

      await readShutdownRequestForMe(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'run',
        now: DateTime(2026, 9, 28, 11),
      );

      final file = File(
        p.join(logs.path, shutdownRequestFileNameFor('PC922', 'run')),
      );
      expect(await file.exists(), isFalse);
    });
  });

  group('φίλτρο βάσης', () {
    test('σημείωμα για άλλη βάση του ίδιου φακέλου αγνοείται', () async {
      await writeShutdownRequest(
        logsDirectory: logs.path,
        toStation: 'PC922',
        toInstance: 'run',
        request: StationShutdownRequest(
          fromStation: 'PC901',
          requestedAt: DateTime(2026, 9, 28, 10),
          immediate: false,
          database: 'lampa.db',
        ),
      );

      final got = await readShutdownRequestForMe(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'run',
        myDatabase: 'hospital.db',
        now: DateTime(2026, 9, 28, 10, 0, 30),
      );

      expect(got, isNull);
    });

    test('όταν λείπει το όνομα βάσης, το σημείωμα μετράει', () async {
      await writeShutdownRequest(
        logsDirectory: logs.path,
        toStation: 'PC922',
        toInstance: 'run',
        request: StationShutdownRequest(
          fromStation: 'PC901',
          requestedAt: DateTime(2026, 9, 28, 10),
          immediate: false,
        ),
      );

      final got = await readShutdownRequestForMe(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'run',
        myDatabase: 'hospital.db',
        now: DateTime(2026, 9, 28, 10, 0, 30),
      );

      expect(got, isNotNull);
    });
  });

  group('κατανάλωση', () {
    test('το μάζεμα αφήνει καθαρό φάκελο για την επόμενη εκκίνηση', () async {
      await writeShutdownRequest(
        logsDirectory: logs.path,
        toStation: 'PC922',
        toInstance: 'run',
        request: StationShutdownRequest(
          fromStation: 'PC901',
          requestedAt: DateTime(2026, 9, 28, 10),
          immediate: true,
        ),
      );

      await clearShutdownRequestForMe(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'run',
      );

      final got = await readShutdownRequestForMe(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'run',
        now: DateTime(2026, 9, 28, 10, 0, 30),
      );
      expect(got, isNull);
    });

    test('αλλοιωμένο αρχείο δεν κλείνει την εφαρμογή', () async {
      final file = File(
        p.join(logs.path, shutdownRequestFileNameFor('PC922', 'run')),
      );
      await file.writeAsString('{"fromStation": "PC9');

      final got = await readShutdownRequestForMe(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'run',
        now: DateTime(2026, 9, 28, 10),
      );

      expect(got, isNull);
    });

    test('φάκελος που δεν υπάρχει δεν πετάει σφάλμα', () async {
      final got = await readShutdownRequestForMe(
        logsDirectory: p.join(logs.path, 'δεν-υπάρχει'),
        myStation: 'PC922',
        myInstance: 'run',
        now: DateTime(2026, 9, 28, 10),
      );
      expect(got, isNull);
    });
  });

  group('άρνηση', () {
    test('η άρνηση φτάνει στον αιτούντα και μαζεύει το σημείωμα', () async {
      await writeShutdownRequest(
        logsDirectory: logs.path,
        toStation: 'PC922',
        toInstance: 'run',
        request: StationShutdownRequest(
          fromStation: 'PC901',
          requestedAt: DateTime(2026, 9, 28, 10),
          immediate: false,
        ),
      );

      await writeShutdownDenial(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'run',
        now: DateTime(2026, 9, 28, 10, 0, 20),
      );

      final reply = await takeShutdownDenial(
        logsDirectory: logs.path,
        fromStation: 'PC922',
        fromInstance: 'run',
        now: DateTime(2026, 9, 28, 10, 0, 25),
      );

      expect(reply, isNotNull);
      expect(reply!.fromStation, 'PC922');

      final request = File(
        p.join(logs.path, shutdownRequestFileNameFor('PC922', 'run')),
      );
      expect(await request.exists(), isFalse);
    });

    test('η άρνηση διαβάζεται μία φορά και σβήνει', () async {
      await writeShutdownDenial(
        logsDirectory: logs.path,
        myStation: 'PC922',
        myInstance: 'run',
        now: DateTime(2026, 9, 28, 10),
      );

      await takeShutdownDenial(
        logsDirectory: logs.path,
        fromStation: 'PC922',
        fromInstance: 'run',
        now: DateTime(2026, 9, 28, 10, 0, 5),
      );
      final second = await takeShutdownDenial(
        logsDirectory: logs.path,
        fromStation: 'PC922',
        fromInstance: 'run',
        now: DateTime(2026, 9, 28, 10, 0, 6),
      );

      expect(second, isNull);
    });
  });

  test('η εγγραφή δεν αφήνει προσωρινά αρχεία πίσω της', () async {
    await writeShutdownRequest(
      logsDirectory: logs.path,
      toStation: 'PC922',
      toInstance: 'run',
      request: StationShutdownRequest(
        fromStation: 'PC901',
        requestedAt: DateTime(2026, 9, 28, 10),
        immediate: false,
      ),
    );

    final leftovers = await logs
        .list()
        .where((e) => e.path.endsWith('.tmp'))
        .toList();
    expect(leftovers, isEmpty);
  });
}
