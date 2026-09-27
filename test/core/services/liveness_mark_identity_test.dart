// Η ταυτότητα του ίχνους «τρέχω τώρα»: ΜΙΑ εκτέλεση πάνω σε ΜΙΑ βάση.
//
//   flutter test test/core/services/liveness_mark_identity_test.dart

import 'dart:io';

import 'package:call_logger/core/database/schema_upgrade_station_guard.dart';
import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:call_logger/core/services/station_name.dart';
import 'package:flutter_test/flutter_test.dart';

const String _thisStation = 'PICINIO';
final DateTime _now = DateTime(2026, 9, 25, 21, 30);

SessionLivenessMark _mark({
  required String station,
  String? database,
  String? instance,
  Duration ago = const Duration(seconds: 20),
}) => SessionLivenessMark(
  station: station,
  version: '0.57.1',
  startedAt: _now.subtract(const Duration(hours: 1)),
  lastSeen: _now.subtract(ago),
  database: database,
  instance: instance,
);

void main() {
  group('ποια βάση κρατά το ίχνος', () {
    test('συνάδελφος σε ΑΛΛΗ βάση του ίδιου φακέλου δεν μπλοκάρει', () {
      // Το σενάριο που μετρήθηκε 25/09: ο POPINIO δούλευε στη hospital.db και
      // κρατούσε κλειστή την αναβάθμιση της integrity_debug.db, επειδή οι δύο
      // βάσεις μοιράζονται έναν φάκελο logs.
      final holders = freshMarksFromOtherStations(
        marks: [_mark(station: 'POPINIO', database: 'hospital.db')],
        now: _now,
        myStation: _thisStation,
        myDatabase: 'integrity_debug.db',
      );
      expect(holders, isEmpty);
    });

    test('συνάδελφος στην ΙΔΙΑ βάση μπλοκάρει', () {
      final holders = freshMarksFromOtherStations(
        marks: [_mark(station: 'POPINIO', database: 'integrity_debug.db')],
        now: _now,
        myStation: _thisStation,
        myDatabase: 'integrity_debug.db',
      );
      expect(holders, hasLength(1));
    });

    test('η σύγκριση αγνοεί πεζά/κεφαλαία', () {
      // Τα Windows δεν ξεχωρίζουν «Hospital.db» από «hospital.db»· ένα ίχνος
      // γραμμένο με άλλα πεζά είναι ο ίδιος συνάδελφος, όχι άλλος.
      final holders = freshMarksFromOtherStations(
        marks: [_mark(station: 'POPINIO', database: 'Integrity_Debug.DB')],
        now: _now,
        myStation: _thisStation,
        myDatabase: 'integrity_debug.db',
      );
      expect(holders, hasLength(1));
    });

    test('ίχνος ΧΩΡΙΣ δηλωμένη βάση μετράει — η άγνοια δεν ανοίγει πόρτα', () {
      // Συνάδελφος με παλαιότερη εφαρμογή: το ίχνος του δεν λέει βάση. Αν τον
      // αγνοούσαμε, θα γινόταν αόρατος ακριβώς τη στιγμή που τον προστατεύουμε.
      final holders = freshMarksFromOtherStations(
        marks: [_mark(station: 'POPINIO', database: null)],
        now: _now,
        myStation: _thisStation,
        myDatabase: 'integrity_debug.db',
      );
      expect(holders, hasLength(1));
    });

    test('όταν ΕΜΕΙΣ δεν ξέρουμε τη βάση μας, μετράνε όλοι', () {
      final holders = freshMarksFromOtherStations(
        marks: [_mark(station: 'POPINIO', database: 'hospital.db')],
        now: _now,
        myStation: _thisStation,
        myDatabase: null,
      );
      expect(holders, hasLength(1));
    });
  });

  group('ποια εκτέλεση είναι το ίχνος', () {
    test('δεύτερο αντίγραφο στον ΙΔΙΟ υπολογιστή, ίδια βάση → μπλοκάρει', () {
      // Η κανονική έκδοση κρατά τη βάση ανοιχτή· η δοκιμαστική δίπλα της δεν
      // επιτρέπεται να αλλάξει το σχήμα κάτω από τα πόδια της.
      final holders = freshMarksFromOtherStations(
        marks: [
          _mark(
            station: _thisStation,
            database: 'integrity_debug.db',
            instance: 'ΑΛΛΟ-ΑΝΤΙΓΡΑΦΟ',
          ),
        ],
        now: _now,
        myStation: _thisStation,
        myDatabase: 'integrity_debug.db',
        myInstance: 'ΕΓΩ',
      );
      expect(holders, hasLength(1));
    });

    test('το ΔΙΚΟ μου ίχνος δεν μπλοκάρει τον εαυτό του', () {
      final holders = freshMarksFromOtherStations(
        marks: [
          _mark(
            station: _thisStation,
            database: 'integrity_debug.db',
            instance: 'ΕΓΩ',
          ),
        ],
        now: _now,
        myStation: _thisStation,
        myDatabase: 'integrity_debug.db',
        myInstance: 'ΕΓΩ',
      );
      expect(holders, isEmpty);
    });

    test('ίχνος παλιάς μορφής από τον σταθμό μου μένει «δικό μου»', () {
      // Χωρίς instance δεν υπάρχει τρόπος να ξεχωρίσει· ο σταθμός είναι η μόνη
      // ταυτότητα που έχουμε, όπως πριν.
      final holders = freshMarksFromOtherStations(
        marks: [_mark(station: _thisStation, instance: null)],
        now: _now,
        myStation: _thisStation,
        myDatabase: 'integrity_debug.db',
        myInstance: 'ΕΓΩ',
      );
      expect(holders, isEmpty);
    });
  });

  group('το ίχνος ταξιδεύει ακέραιο', () {
    test('βάση και εκτέλεση επιβιώνουν της εγγραφής', () {
      final original = _mark(
        station: 'POPINIO',
        database: 'hospital.db',
        instance: 'C:/app.exe|dev',
      );
      final restored = SessionLivenessMark.decode(original.encode());
      expect(restored?.database, 'hospital.db');
      expect(restored?.instance, 'C:/app.exe|dev');
    });

    test('ίχνος παλιάς έκδοσης διαβάζεται, με κενά τα νέα πεδία', () {
      final restored = SessionLivenessMark.decode(
        '{"station":"POPINIO","version":"0.50.0",'
        '"startedAt":"2026-09-25T20:00:00.000",'
        '"lastSeen":"2026-09-25T21:00:00.000"}',
      );
      expect(restored, isNotNull);
      expect(restored!.station, 'POPINIO');
      expect(restored.database, isNull);
      expect(restored.instance, isNull);
    });
  });

  group('δύο αντίγραφα στον ίδιο υπολογιστή', () {
    late Directory tempRoot;
    late Directory logsDir;

    setUp(() async {
      StationName.reader = () => _thisStation;
      tempRoot = await Directory.systemTemp.createTemp('liveness_identity_');
      logsDir = Directory('${tempRoot.path}${Platform.pathSeparator}logs');
      await logsDir.create(recursive: true);
    });

    tearDown(() async {
      StationName.reader = StationName.defaultReader;
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    });

    CrashLogService serviceFor(String instance) => CrashLogService(
      logsDirectory: logsDir.path,
      appVersion: '0.57.1-test',
      now: () => _now,
      databaseFileName: 'integrity_debug.db',
      instanceId: instance,
    );

    File todayLog() => File(
      '${logsDir.path}${Platform.pathSeparator}'
      '${CrashLogService.dailyLogFileName(_now)}',
    );

    test('κάθε αντίγραφο γράφει ΔΙΚΟ του αρχείο ίχνους', () async {
      await serviceFor('ΚΑΝΟΝΙΚΗ').onStartup(retentionCount: 14);
      await serviceFor('ΔΟΚΙΜΑΣΤΙΚΗ').onStartup(retentionCount: 14);

      final locks = logsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.lock'))
          .toList();
      expect(locks, hasLength(2));
    });

    test('το ζωντανό αντίγραφο δίπλα μου ΔΕΝ είναι κατάρρευση', () async {
      // Το εύρημα της 23/09: η δεύτερη εφαρμογή έγραφε ΚΡΙΣΙΜΟ «η προηγούμενη
      // εκτέλεση δεν τερμάτισε ομαλά» ενώ η πρώτη έτρεχε ακόμη.
      await serviceFor('ΚΑΝΟΝΙΚΗ').onStartup(retentionCount: 14);
      await serviceFor('ΔΟΚΙΜΑΣΤΙΚΗ').onStartup(retentionCount: 14);

      expect(
        todayLog().existsSync(),
        isFalse,
        reason: 'καμία αναφορά κατάρρευσης για εκτέλεση που τρέχει',
      );
    });

    test('το ομαλό κλείσιμο του ενός αφήνει το ίχνος του άλλου', () async {
      // Το δεύτερο σκέλος: όταν μοιράζονταν αρχείο, το κλείσιμο του ενός
      // έσβηνε το ίχνος του άλλου — και μια πραγματική κατάρρευσή του μετά
      // από αυτό δεν άφηνε κανένα ίχνος.
      final normal = serviceFor('ΚΑΝΟΝΙΚΗ');
      final debug = serviceFor('ΔΟΚΙΜΑΣΤΙΚΗ');
      await normal.onStartup(retentionCount: 14);
      await debug.onStartup(retentionCount: 14);

      await debug.onShutdown();

      final locks = logsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.lock'))
          .toList();
      expect(locks, hasLength(1), reason: 'μένει το ίχνος της κανονικής');
      final surviving = SessionLivenessMark.decode(
        locks.single.readAsStringSync(),
      );
      expect(surviving?.instance, 'ΚΑΝΟΝΙΚΗ');
    });

    test('η δική μου προηγούμενη εκτέλεση εξακολουθεί να αναφέρεται', () async {
      // Δεν χαλαρώνει ο φρουρός: κατάρρευση του ΙΔΙΟΥ αντιγράφου πρέπει να
      // εξακολουθεί να φαίνεται στην επόμενη εκκίνησή του.
      await serviceFor('ΚΑΝΟΝΙΚΗ').onStartup(retentionCount: 14);
      await serviceFor('ΚΑΝΟΝΙΚΗ').onStartup(retentionCount: 14);

      expect(todayLog().existsSync(), isTrue);
      expect(todayLog().readAsStringSync(), contains('δεν τερμάτισε ομαλά'));
    });

    test('το ίχνος δηλώνει ποια βάση κρατούσε', () async {
      await serviceFor('ΚΑΝΟΝΙΚΗ').onStartup(retentionCount: 14);

      final lock = logsDir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.lock'),
      );
      final mark = SessionLivenessMark.decode(lock.readAsStringSync());
      expect(mark?.database, 'integrity_debug.db');
    });
  });
}
