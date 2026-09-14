// Ο κριτής της επαναφοράς: ποια βάση αντιγράφου επιτρέπεται να αντικαταστήσει
// την ενεργή.
//
// Συμβόλαιο: καμία βάση δεν γίνεται ενεργή χωρίς να έχει περάσει τον ίδιο
// έλεγχο με την αλλαγή βάσης — και ο έλεγχος τρέχει ΠΡΙΝ αντικατασταθεί
// οτιδήποτε. Εύρημα 13/09/2026: μια βάση χωρίς τους πίνακες phones και
// departments επαναφέρθηκε κανονικά και έριξε την εφαρμογή, χωρίς διέξοδο.
//
//   flutter test test/features/database/services/restore_database_eligibility_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_schema_version.dart';
import 'package:call_logger/features/database/services/restore_database_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Το σχήμα δεν λέει τίποτα για το αν το περιεχόμενο στέκει. Μια βάση με
  // σωστούς πίνακες και μισές σελίδες μηδενισμένες δίνει ακριβώς το ίδιο
  // προφίλ με μια υγιή — γι' αυτό οι έλεγχοι εδώ δουλεύουν σε ΠΡΑΓΜΑΤΙΚΟ
  // αρχείο, όχι σε χειροποίητο DatabaseFileProfile.
  group('αλλοιωμένο περιεχόμενο', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('eligibility_integrity_');
    });

    tearDown(() {
      try {
        if (root.existsSync()) root.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<String> buildDatabase({required bool corrupt}) async {
      final path = p.join(root.path, corrupt ? 'σάπια.db' : 'υγιής.db');
      final db = await databaseFactory.openDatabase(path);
      for (final table in const <String>[
        'calls',
        'users',
        'phones',
        'equipment',
        'departments',
        'categories',
        'tasks',
      ]) {
        await db.execute(
          'CREATE TABLE $table (id INTEGER PRIMARY KEY, date TEXT, note TEXT)',
        );
      }
      // Αρκετές εγγραφές ώστε η βάση να ξεπεράσει τη μία σελίδα και η φθορά
      // να πέσει σε πραγματικά δεδομένα, όχι σε κενό χώρο.
      final batch = db.batch();
      for (var i = 0; i < 800; i++) {
        batch.insert('calls', {
          'date': '2026-09-13',
          'note': 'κλήση $i — ${'γ' * 120}',
        });
      }
      await batch.commit(noResult: true);
      await db.execute('PRAGMA user_version = 59');
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

    test('υγιής βάση με πλήρες σχήμα επαναφέρεται', () async {
      final verdict = judgeBackupDatabase(
        await profileDatabaseFile(await buildDatabase(corrupt: false)),
      );
      expect(verdict.restorable, isTrue);
      expect(verdict.reason, isNull);
    });

    test('υγιής βάση δεν ζητά δεύτερη επιβεβαίωση', () async {
      final verdict = judgeBackupDatabase(
        await profileDatabaseFile(await buildDatabase(corrupt: false)),
      );
      expect(verdict.requiresConfirmation, isFalse);
    });

    test(
      'βάση με κατεστραμμένο περιεχόμενο ΔΕΝ επαναφέρεται σιωπηλά',
      () async {
        final path = await buildDatabase(corrupt: true);
        final profile = await profileDatabaseFile(path);

        // Η παγίδα σε μία γραμμή: το σχήμα είναι άψογο. Ό,τι κρίνει μόνο
        // πίνακες και έκδοση λέει «ναι» σε ένα αρχείο που δεν διαβάζεται.
        expect(
          profile.kind,
          DatabaseFileKind.callLogger,
          reason: 'Οι επτά πίνακες υπάρχουν — η φθορά είναι στο περιεχόμενο',
        );
        expect(
          profile.contentIsCorrupt,
          isTrue,
          reason: 'Το ίδιο το SQLite το δηλώνει, δεν το συμπεραίνουμε εμείς',
        );

        final verdict = judgeBackupDatabase(profile);
        expect(
          verdict.requiresConfirmation,
          isTrue,
          reason:
              'Η επαναφορά επιτρέπεται —μπορεί να είναι το μόνο αντίγραφο— '
              'αλλά ποτέ χωρίς ρητή απόφαση του χρήστη',
        );
        expect(verdict.reason, isNotNull);
        expect(
          verdict.technicalDetail,
          isNotNull,
          reason: 'Το ωμό κείμενο του SQLite ταξιδεύει ως τη δεύτερη ερώτηση',
        );
      },
    );

    test('φθορά δεν συμπεραίνεται από σιωπή', () {
      // Προφίλ φτιαγμένο χωρίς να τρέξει έλεγχος (π.χ. από τεστ ή από ροή
      // που δεν άνοιξε το αρχείο): «δεν ξέρω» ΔΕΝ σημαίνει «χαλασμένο».
      const unchecked = DatabaseFileProfile(kind: DatabaseFileKind.callLogger);
      expect(unchecked.contentIsCorrupt, isFalse);
      expect(judgeBackupDatabase(unchecked).requiresConfirmation, isFalse);
    });
  });

  test('πλήρης βάση της Καταγραφής επαναφέρεται', () {
    const profile = DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      userVersion: 59,
    );
    expect(judgeBackupDatabase(profile).restorable, isTrue);
    expect(judgeBackupDatabase(profile).reason, isNull);
  });

  test('βάση ΝΕΟΤΕΡΗΣ έκδοσης απορρίπτεται ΠΡΙΝ γραφτεί πάνω στην ενεργή', () {
    // Το σενάριο του πεδίου: αντίγραφο φτιαγμένο από νεότερη εγκατάσταση.
    // Το σχήμα είναι άψογο και το περιεχόμενο υγιές — τίποτα από όσα έκρινε ο
    // κριτής δεν το σταματούσε. Η απόρριψη ερχόταν αργότερα, από το άνοιγμα,
    // όταν η βάση εργασίας είχε ήδη αντικατασταθεί.
    final profile = DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      userVersion: kDatabaseSchemaVersion + 1,
    );
    final verdict = judgeBackupDatabase(profile);
    expect(verdict.restorable, isFalse);
    expect(
      verdict.requiresConfirmation,
      isFalse,
      reason: 'Δεν προσφέρεται ως ρίσκο — καμία νεότερη βάση δεν ανοίγει εδώ',
    );
    expect(verdict.reason, contains('${kDatabaseSchemaVersion + 1}'));
  });

  test('η τρέχουσα έκδοση σχήματος επαναφέρεται κανονικά', () {
    const profile = DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      userVersion: kDatabaseSchemaVersion,
    );
    expect(judgeBackupDatabase(profile).restorable, isTrue);
  });

  test('παλαιότερη έκδοση σχήματος ΔΕΝ είναι λόγος απόρριψης', () {
    // Το αρχείο «maria.db» του σεναρίου: έκδοση 17 με πλήρες σχήμα. Η
    // αναβάθμιση είναι δουλειά των μεταπτώσεων, όχι του κριτή.
    const profile = DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      userVersion: 17,
    );
    expect(judgeBackupDatabase(profile).restorable, isTrue);
  });

  test('ελλιπής βάση απορρίπτεται, ονομάζοντας τους πίνακες που λείπουν', () {
    const profile = DatabaseFileProfile(
      kind: DatabaseFileKind.incompleteCallLogger,
      missingCoreTables: ['phones', 'departments'],
      userVersion: 1,
    );
    final verdict = judgeBackupDatabase(profile);
    expect(verdict.restorable, isFalse);
    expect(verdict.reason, contains('phones'));
    expect(verdict.reason, contains('departments'));
  });

  test(
    'βάση Λάμπας, υβρίδιο, κενό και άγνωστο απορρίπτονται με δικό τους λόγο',
    () {
      final reasons = <DatabaseFileKind, String?>{};
      for (final kind in [
        DatabaseFileKind.lamp,
        DatabaseFileKind.hybrid,
        DatabaseFileKind.empty,
        DatabaseFileKind.unknown,
      ]) {
        final verdict = judgeBackupDatabase(DatabaseFileProfile(kind: kind));
        expect(verdict.restorable, isFalse, reason: '$kind');
        expect(verdict.reason, isNotNull, reason: '$kind');
        reasons[kind] = verdict.reason;
      }
      expect(
        reasons.values.toSet().length,
        reasons.length,
        reason: 'Κάθε λόγος απόρριψης λέει κάτι διαφορετικό στον χρήστη',
      );
    },
  );

  test(
    'αρχείο που δεν ελέγχθηκε απορρίπτεται — δεν δίνεται το όφελος της αμφιβολίας',
    () {
      const profile = DatabaseFileProfile(kind: DatabaseFileKind.undetermined);
      expect(judgeBackupDatabase(profile).restorable, isFalse);
    },
  );

  test('χωρίς προφίλ καθόλου, δεν επαναφέρεται', () {
    final verdict = judgeBackupDatabase(null);
    expect(verdict.restorable, isFalse);
    expect(verdict.reason, isNotNull);
  });
}
