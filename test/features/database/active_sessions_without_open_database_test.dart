// Ο φρουρός «ποιος άλλος κρατά τη βάση» πριν από επικίνδυνη ενέργεια (π.χ.
// μόνιμη αναβάθμιση σχήματος στην εκκίνηση). Διάβαζε τη λίστα ΜΟΝΟ από τη
// βάση — και στην εκκίνηση η βάση δεν έχει ανοίξει, οπότε η λίστα έβγαινε
// κενή και ο φρουρός σώπαινε ακριβώς εκεί που χρειαζόταν.
//
// Χωρίς ανοιχτή βάση, η λίστα έρχεται από τα ίχνη «τρέχω τώρα» που γράφει
// κάθε σταθμός στον φάκελο logs δίπλα στη βάση.
//
//   flutter test test/features/database/active_sessions_without_open_database_test.dart

import 'dart:io';

import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:call_logger/core/services/station_name.dart';
import 'package:call_logger/features/database/providers/active_sessions_provider.dart';
import 'package:call_logger/features/database/services/active_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final now = DateTime(2026, 9, 23, 22, 15);
  late Directory logs;
  late String Function() originalStationReader;

  Future<void> writeMark(
    String fileName, {
    required String station,
    required String version,
    required DateTime lastSeen,
  }) async {
    await File(p.join(logs.path, fileName)).writeAsString(
      SessionLivenessMark(
        station: station,
        version: version,
        startedAt: lastSeen.subtract(const Duration(hours: 1)),
        lastSeen: lastSeen,
      ).encode(),
    );
  }

  setUp(() async {
    logs = await Directory.systemTemp.createTemp('active_sessions_logs_');
    originalStationReader = StationName.reader;
    StationName.reader = () => 'PICINIO';
  });

  tearDown(() async {
    StationName.reader = originalStationReader;
    if (await logs.exists()) await logs.delete(recursive: true);
  });

  test('βάση κλειστή, συνάδελφος ζωντανός: ο φρουρός τον βλέπει', () async {
    await writeMark(
      'session_POPINIO.lock',
      station: 'POPINIO',
      version: '0.56.0',
      lastSeen: now.subtract(const Duration(seconds: 40)),
    );

    final sessions = await loadActiveSessions(
      now: now,
      logsDirectory: logs.path,
    );

    final others = otherSessions(sessions);
    expect(others.map((s) => s.station), ['POPINIO']);
    expect(
      others.single.appVersion,
      '0.56.0',
      reason: 'η διαφορά έκδοσης είναι ακριβώς ό,τι κρίνει μια αναβάθμιση',
    );
  });

  test('το δικό μου ίχνος δεν μετρά ως «άλλος»', () async {
    await writeMark(
      'session_PICINIO.lock',
      station: 'PICINIO',
      version: '0.57.1',
      lastSeen: now,
    );

    final sessions = await loadActiveSessions(
      now: now,
      logsDirectory: logs.path,
    );

    expect(otherSessions(sessions), isEmpty);
    expect(myAppVersion(sessions), '0.57.1');
  });

  test('ίχνος που έπαψε να ανανεώνεται (κατάρρευση) δεν μετρά', () async {
    // Το ίχνος σβήνει μόνο στο ομαλό κλείσιμο· μετά από κατάρρευση μένει, και
    // χωρίς όριο φρεσκάδας θα φώναζε για κάποιον που δεν είναι εκεί.
    await writeMark(
      'session_POPINIO.lock',
      station: 'POPINIO',
      version: '0.56.0',
      lastSeen: now.subtract(const Duration(minutes: 10)),
    );

    final sessions = await loadActiveSessions(
      now: now,
      logsDirectory: logs.path,
    );

    expect(otherSessions(sessions), isEmpty);
  });

  test('αλλοιωμένο ίχνος αγνοείται, τα υγιή διαβάζονται', () async {
    await File(
      p.join(logs.path, 'session_XALASMENO.lock'),
    ).writeAsString('δεν είναι JSON');
    await writeMark(
      'session_POPINIO.lock',
      station: 'POPINIO',
      version: '0.57.1',
      lastSeen: now,
    );

    final sessions = await loadActiveSessions(
      now: now,
      logsDirectory: logs.path,
    );

    expect(otherSessions(sessions).map((s) => s.station), ['POPINIO']);
  });

  test('φάκελος που δεν υπάρχει: κενή λίστα, χωρίς σφάλμα', () async {
    final sessions = await loadActiveSessions(
      now: now,
      logsDirectory: p.join(logs.path, 'den_yparxei'),
    );

    expect(sessions, isEmpty);
  });
}
