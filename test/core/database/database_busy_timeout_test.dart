// Πόσο περιμένει μια εγγραφή όταν τη βάση την κρατά ήδη κάποιος άλλος.
//
// Μετρημένο σε πραγματική κοινόχρηστη βάση (18/08/2026, \\gnk.local) με δύο
// ξεχωριστές εφαρμογές: χωρίς αναμονή ο δεύτερος γραφέας αποτυγχάνει σε 3
// χιλιοστά με «database is locked» — και στους ΔΥΟ τρόπους ημερολογίου. Με
// αναμονή περνά κανονικά μόλις ελευθερωθεί η βάση (2,8 δευτερόλεπτα).
//
// Δηλαδή η εφαρμογή, όπως ήταν, δεν άντεχε δύο ανθρώπους να σώζουν κλήση την
// ίδια στιγμή — ανεξάρτητα από WAL.
//
//   flutter test test/core/database/database_busy_timeout_test.dart

import 'dart:io';

import 'package:call_logger/core/config/app_config.dart';
import 'package:call_logger/core/database/database_busy_timeout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_busy_timeout_test');
  });

  group('πόση αναμονή δίνεται, ανάλογα με το πού ζει η βάση', () {
    test('δικτυακή διαδρομή παίρνει τη γενναιόδωρη αναμονή', () {
      expect(
        resolveDatabaseBusyTimeoutMs(
          r'\\gnk.local\Departments\TPO\Call Logger\call_logger.db',
        ),
        AppConfig.databaseBusyTimeoutNetworkMs,
      );
    });

    test('τοπική διαδρομή παίρνει τη μικρότερη', () {
      expect(
        resolveDatabaseBusyTimeoutMs(r'C:\Users\x\Documents\call_logger.db'),
        AppConfig.databaseBusyTimeoutLocalMs,
      );
    });

    test('η δικτυακή αναμονή είναι μεγαλύτερη από την τοπική', () {
      // Το δίκτυο αργεί· η αναμονή που φτάνει τοπικά δεν φτάνει εκεί.
      expect(
        AppConfig.databaseBusyTimeoutNetworkMs,
        greaterThan(AppConfig.databaseBusyTimeoutLocalMs),
      );
    });

    test('καμία από τις δύο δεν είναι μηδέν', () {
      // Μηδέν σημαίνει «παραιτήσου αμέσως» — ακριβώς η συμπεριφορά που
      // αποτύγχανε στα 3 χιλιοστά.
      expect(AppConfig.databaseBusyTimeoutLocalMs, greaterThan(0));
      expect(AppConfig.databaseBusyTimeoutNetworkMs, greaterThan(0));
    });
  });

  group('η ρύθμιση φτάνει όντως στη σύνδεση', () {
    test('μετά την εφαρμογή, η σύνδεση αναφέρει τη σωστή τιμή', () async {
      final path = p.join(tempDir.path, 'syndesi.db');
      final db = await openDatabase(path, singleInstance: false);

      // Η SQLite ξεκινά κάθε σύνδεση χωρίς αναμονή.
      expect(await readDatabaseBusyTimeoutMs(db), 0);

      await applyDatabaseBusyTimeout(db, path);

      expect(
        await readDatabaseBusyTimeoutMs(db),
        AppConfig.databaseBusyTimeoutLocalMs,
      );
      await db.close();
    });

    test('είναι ρύθμιση σύνδεσης, όχι ιδιότητα του αρχείου', () async {
      // Δεύτερη σύνδεση στο ΙΔΙΟ αρχείο ξεκινά πάλι από το μηδέν — γι' αυτό
      // μπαίνει σε κάθε άνοιγμα, όχι μία φορά στη ζωή της βάσης.
      final path = p.join(tempDir.path, 'koini.db');
      final first = await openDatabase(path, singleInstance: false);
      await applyDatabaseBusyTimeout(first, path);
      expect(
        await readDatabaseBusyTimeoutMs(first),
        AppConfig.databaseBusyTimeoutLocalMs,
      );
      await first.close();

      final second = await openDatabase(path, singleInstance: false);
      expect(await readDatabaseBusyTimeoutMs(second), 0);
      await second.close();
    });

    test('η αναμονή του onConfigure επιβιώνει ως την κανονική χρήση', () async {
      // Το onConfigure τρέχει πριν από onCreate/onUpgrade/onOpen — εκεί
      // μπαίνει, ώστε να προστατεύει και τις μεταπτώσεις σχήματος, που κι
      // εκείνες γράφουν. Ελέγχεται ότι δεν χάνεται στη διαδρομή.
      final path = p.join(tempDir.path, 'kyklos.db');
      final db = await openDatabase(
        path,
        version: 1,
        onConfigure: (d) => applyDatabaseBusyTimeout(d, path),
        onCreate: (d, _) async =>
            d.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)'),
        singleInstance: false,
      );

      expect(
        await readDatabaseBusyTimeoutMs(db),
        AppConfig.databaseBusyTimeoutLocalMs,
      );
      await db.close();
    });
  });

  group('τι κάνει η αναμονή σε πραγματικό κλείδωμα', () {
    // Η ΕΠΙΤΥΧΙΑ του δεύτερου γραφέα δεν ελέγχεται μέσα σε ένα τεστ: το
    // sqflite_common_ffi εξυπηρετεί όλες τις συνδέσεις από το ίδιο υπόβαθρο,
    // οπότε όσο ο δεύτερος μπλοκάρει, το COMMIT του πρώτου δεν προλαβαίνει να
    // εκτελεστεί. Στην πραγματικότητα οι δύο γραφείς είναι ΞΕΧΩΡΙΣΤΕΣ
    // εφαρμογές — εκεί επαληθεύτηκε ζωντανά στην κοινόχρηστη βάση.
    //
    // Εδώ ελέγχεται το ντετερμινιστικό κομμάτι: πόσο κρατιέται ο γραφέας πριν
    // παραιτηθεί. Αυτό ακριβώς αλλάζει η ρύθμιση.
    Future<int> heldForMs(Directory dir, int busyMs) async {
      final path = p.join(dir.path, 'anamoni_$busyMs.db');
      final holder = await openDatabase(path, singleInstance: false);
      await holder.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      final writer = await openDatabase(path, singleInstance: false);
      await writer.execute('PRAGMA busy_timeout = $busyMs');

      await holder.execute('BEGIN IMMEDIATE');
      await holder.rawInsert('INSERT INTO t (id) VALUES (1)');

      final sw = Stopwatch()..start();
      try {
        await writer.rawInsert('INSERT INTO t (id) VALUES (2)');
      } catch (_) {
        // Αναμενόμενο· μας ενδιαφέρει ΠΟΣΟ κρατήθηκε, όχι αν πέρασε.
      }
      sw.stop();

      try {
        await holder.execute('COMMIT');
      } catch (_) {}
      await writer.close();
      await holder.close();
      return sw.elapsedMilliseconds;
    }

    test('χωρίς αναμονή παραιτείται αμέσως, με αναμονή κρατιέται', () async {
      final withoutWait = await heldForMs(tempDir, 0);
      final withWait = await heldForMs(tempDir, 1200);

      expect(withoutWait, lessThan(400), reason: 'η παλιά συμπεριφορά');
      expect(withWait, greaterThan(900), reason: 'κρατήθηκε όσο του ζητήθηκε');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
