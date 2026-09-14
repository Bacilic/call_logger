// Το κενό και το «δεν διαβάζεται» είναι διαφορετικές απαντήσεις.
//
// Σενάριο 13/09 (Δ4): στη σύγκριση «Τρέχουσα / Αντίγραφο» φθαρμένης βάσης
// δύο γραμμές γύρισαν «—» ενώ οι υπόλοιπες έδειχναν κανονικούς αριθμούς.
// Το ίδιο σύμβολο σήμαινε και «δεν υπάρχει τίποτα» και «αυτό το κομμάτι της
// βάσης δεν διαβάζεται» — τη στιγμή ακριβώς που κρίνεται η επαναφορά.
//
// Μετρημένο 14/09 σε πραγματική φθαρμένη βάση: κλήσεις και υπάλληλοι
// γύρισαν null (δεν διαβάστηκαν), τηλέφωνα 0 και εξοπλισμός 400 (διαβάστηκαν).
//
//   flutter test test/core/database/database_profile_unreadable_metrics_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _coreTables = <String>[
  'calls',
  'users',
  'phones',
  'equipment',
  'departments',
  'categories',
  'tasks',
];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('unreadable-metrics-');
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<String> buildDatabase({required bool corrupt, int calls = 800}) async {
    final path = p.join(root.path, corrupt ? 'σάπια.db' : 'υγιής.db');
    final db = await databaseFactory.openDatabase(path);
    for (final table in _coreTables) {
      await db.execute(
        'CREATE TABLE $table (id INTEGER PRIMARY KEY, date TEXT, note TEXT)',
      );
    }
    final batch = db.batch();
    for (var i = 0; i < calls; i++) {
      batch.insert('calls', {
        'date': '2026-09-13',
        'note': 'κλήση $i — ${'γ' * 120}',
      });
    }
    for (var i = 0; i < 400; i++) {
      batch.insert('users', {'note': 'χρήστης $i — ${'δ' * 120}'});
    }
    for (var i = 0; i < 400; i++) {
      batch.insert('equipment', {'note': 'μηχάνημα $i — ${'ε' * 120}'});
    }
    await batch.commit(noResult: true);
    await db.execute('PRAGMA user_version = 60');
    await db.close();

    if (corrupt) {
      final file = File(path);
      final bytes = await file.readAsBytes();
      for (var i = bytes.length ~/ 3; i < (bytes.length * 2) ~/ 3; i++) {
        bytes[i] = 0x00;
      }
      await file.writeAsBytes(bytes, flush: true);
    }
    return path;
  }

  test('υγιής βάση: καμία μέτρηση δεν λείπει', () async {
    final profile = await profileDatabaseFile(
      await buildDatabase(corrupt: false),
    );
    expect(profile.unreadableMetrics, isEmpty);
    expect(profile.callCount, 800);
  });

  test('υγιής βάση ΧΩΡΙΣ κλήσεις: κενό, όχι σφάλμα', () async {
    // Η καρδιά του ευρήματος: εδώ η τελευταία κλήση είναι `null` επειδή
    // ΔΕΝ ΥΠΑΡΧΕΙ καμία — και δεν επιτρέπεται να μοιάσει με βλάβη.
    final profile = await profileDatabaseFile(
      await buildDatabase(corrupt: false, calls: 0),
    );
    expect(profile.callCount, 0);
    expect(profile.latestCallDate, isNull);
    expect(
      profile.isUnreadable(DatabaseProfileMetric.latestCall),
      isFalse,
      reason: 'Καμία κλήση δεν είναι βλάβη',
    );
  });

  test('φθαρμένη βάση: οι μετρήσεις που απέτυχαν ονομάζονται', () async {
    final profile = await profileDatabaseFile(
      await buildDatabase(corrupt: true),
    );
    expect(profile.contentIsCorrupt, isTrue);
    expect(
      profile.unreadableMetrics,
      isNotEmpty,
      reason: 'Κάποια ερωτήματα έσκασαν πάνω στις χαλασμένες σελίδες',
    );

    // Ό,τι γύρισε `null` το γύρισε επειδή απέτυχε, και το λέει.
    for (final entry in <DatabaseProfileMetric, int?>{
      DatabaseProfileMetric.calls: profile.callCount,
      DatabaseProfileMetric.users: profile.userCount,
      DatabaseProfileMetric.phones: profile.phoneCount,
      DatabaseProfileMetric.equipment: profile.equipmentCount,
      DatabaseProfileMetric.departments: profile.departmentCount,
    }.entries) {
      if (entry.value == null) {
        expect(
          profile.isUnreadable(entry.key),
          isTrue,
          reason: 'Το ${entry.key.name} βγήκε κενό χωρίς να πει γιατί',
        );
      } else {
        expect(
          profile.isUnreadable(entry.key),
          isFalse,
          reason: 'Το ${entry.key.name} διαβάστηκε — δεν είναι σφάλμα',
        );
      }
    }
  });

  test('προφίλ χωρίς μετρήσεις δεν ισχυρίζεται βλάβη', () async {
    // Η προεπιλογή: όποιος φτιάχνει προφίλ στο χέρι δεν κατηγορεί το αρχείο.
    const profile = DatabaseFileProfile(kind: DatabaseFileKind.callLogger);
    expect(profile.unreadableMetrics, isEmpty);
    for (final metric in DatabaseProfileMetric.values) {
      expect(profile.isUnreadable(metric), isFalse);
    }
  });
}
