// Δοκιμαστικό άνοιγμα βάσης: η μόνη απόδειξη ότι ένα αρχείο ανοίγει.
//
// Σενάριο 14/09 (Δ2): δύο αρχεία περνούσαν καθαρά τον κριτή της επαναφοράς,
// αντικαθιστούσαν τη βάση εργασίας, και μετά έριχναν την εφαρμογή:
//   · επτά πίνακες με ετικέτα έκδοσης 0  → «table calls already exists»
//   · επτά πίνακες με ετικέτα έκδοσης 17 → «no such table: audit_log»
// Ο κριτής κοιτούσε ονόματα πινάκων και έναν αριθμό· το άνοιγμα αποφασίζει
// με άλλο ερώτημα — θα δημιουργήσει σχήμα ή θα το αναβαθμίσει;
//
//   flutter test test/core/database/database_open_trial_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_integrity_probe.dart';
import 'package:call_logger/core/database/database_open_trial.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/features/database/services/restore_database_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Οι επτά πίνακες που κάνουν ένα αρχείο «βάση της Καταγραφής Κλήσεων» στα
/// μάτια του ταξινομητή — χωρίς τίποτα από όσα προσθέτουν οι μεταπτώσεις.
const _coreTables = <String, String>{
  'calls': 'id INTEGER PRIMARY KEY, date TEXT, description TEXT',
  'users': 'id INTEGER PRIMARY KEY, name TEXT',
  'phones': 'id INTEGER PRIMARY KEY, number TEXT',
  'equipment': 'id INTEGER PRIMARY KEY, code_equipment TEXT, name TEXT',
  'departments': 'id INTEGER PRIMARY KEY, name TEXT',
  'categories': 'id INTEGER PRIMARY KEY, name TEXT',
  'tasks': 'id INTEGER PRIMARY KEY, title TEXT',
};

/// Λατινικά που προδίδουν ωμό SQL μέσα σε κείμενο για τον χειριστή.
const _rawSqlWords = <String>[
  'table',
  'TABLE',
  'no such',
  'already exists',
  'SQL',
  'sqlite',
  'SQLite',
];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('open-trial-');
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Αρχείο με τους επτά πίνακες και ελεγχόμενη ετικέτα έκδοσης.
  Future<String> labelledDatabase(int version) async {
    final path = p.join(root.path, 'ετικέτα_$version.db');
    final db = await databaseFactory.openDatabase(path);
    for (final entry in _coreTables.entries) {
      await db.execute('CREATE TABLE ${entry.key} (${entry.value})');
    }
    await db.execute('PRAGMA user_version = $version');
    await db.close();
    return path;
  }

  /// Αρχείο με το ΠΡΑΓΜΑΤΙΚΟ σχήμα της τρέχουσας έκδοσης.
  Future<String> currentSchemaDatabase() async {
    final path = p.join(root.path, 'υγιής.db');
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: kDatabaseSchemaVersion,
        onCreate: onDatabaseCreate,
        onUpgrade: onDatabaseUpgradeSquashed,
      ),
    );
    await db.close();
    return path;
  }

  group('τι απαντά η δοκιμή', () {
    test('ετικέτα 0 με υπαρκτούς πίνακες: αποδεδειγμένα δεν ανοίγει', () async {
      final trial = await trialOpenDatabase(await labelledDatabase(0));
      expect(trial.provenToFail, isTrue);
      expect(trial.technicalDetail, contains('already exists'));
    });

    test('ετικέτα 17 με σχήμα που δεν είναι του 17: δεν ανοίγει', () async {
      final trial = await trialOpenDatabase(await labelledDatabase(17));
      expect(trial.provenToFail, isTrue);
      expect(trial.technicalDetail, contains('audit_log'));
    });

    test('βάση της τρέχουσας έκδοσης ανοίγει κανονικά', () async {
      final trial = await trialOpenDatabase(await currentSchemaDatabase());
      expect(trial.status, DatabaseOpenTrialStatus.opens);
      expect(trial.reason, isNull);
    });

    test(
      'αρχείο που δεν υπάρχει δεν κατηγορείται — απλώς δεν κρίθηκε',
      () async {
        final trial = await trialOpenDatabase(
          p.join(root.path, 'ανύπαρκτο.db'),
        );
        expect(trial.status, DatabaseOpenTrialStatus.inconclusive);
        expect(
          trial.provenToFail,
          isFalse,
          reason: 'Αδυναμία δοκιμής δεν είναι απόδειξη βλάβης',
        );
      },
    );
  });

  group('το πρωτότυπο μένει ανέγγιχτο', () {
    test('η επιτυχημένη δοκιμή δεν αλλάζει ούτε ένα byte', () async {
      final path = await currentSchemaDatabase();
      final before = await File(path).readAsBytes();
      await trialOpenDatabase(path);
      expect(await File(path).readAsBytes(), equals(before));
    });

    test(
      'η αποτυχημένη δοκιμή δεν αφήνει σκουπίδια δίπλα στο αρχείο',
      () async {
        final path = await labelledDatabase(17);
        await trialOpenDatabase(path);
        final leftovers = Directory(
          root.path,
        ).listSync().map((e) => p.basename(e.path)).toList();
        expect(leftovers, <String>[p.basename(path)]);
      },
    );
  });

  group('τι διαβάζει ο χειριστής', () {
    test('η ετικέτα 0 εξηγείται χωρίς λέξη SQL', () {
      final reason = databaseOpenTrialReason(
        declaredVersion: 0,
        appSchemaVersion: 60,
      );
      expect(reason, contains('δεν'));
      expect(reason, contains('έκδοση σχήματος'));
      for (final word in _rawSqlWords) {
        expect(reason, isNot(contains(word)));
      }
    });

    test('η ασυμφωνία ονομάζει και τις δύο εκδόσεις', () {
      final reason = databaseOpenTrialReason(
        declaredVersion: 17,
        appSchemaVersion: 60,
      );
      expect(reason, contains('17'));
      expect(reason, contains('60'));
      for (final word in _rawSqlWords) {
        expect(reason, isNot(contains(word)));
      }
    });

    test('κάθε άρνηση προτείνει διέξοδο', () {
      for (final version in <int?>[null, 0, 17, 60, 99]) {
        expect(
          databaseOpenTrialReason(
            declaredVersion: version,
            appSchemaVersion: 60,
          ),
          contains('αντίγραφο'),
        );
      }
    });
  });

  group('ο κριτής της επαναφοράς', () {
    test('αποδεδειγμένη αποτυχία ανοίγματος κλειδώνει την επαναφορά', () async {
      final path = await labelledDatabase(0);
      final verdict = judgeBackupDatabase(
        await profileDatabaseFile(path),
        openTrial: await trialOpenDatabase(path),
      );
      expect(verdict.restorable, isFalse);
      for (final word in _rawSqlWords) {
        expect(verdict.reason, isNot(contains(word)));
      }
      expect(verdict.technicalDetail, isNotNull);
    });

    test('χωρίς δοκιμή, η κρίση μένει όπως ήταν', () async {
      final path = await currentSchemaDatabase();
      expect(
        judgeBackupDatabase(await profileDatabaseFile(path)).restorable,
        isTrue,
      );
    });

    test('η φθορά παραμένει απόφαση του χρήστη, όχι άρνηση', () {
      // Απόφαση Διευθυντή 13/09: φθαρμένη βάση = προειδοποίηση με δεύτερη
      // επιβεβαίωση, γιατί μπορεί να είναι το μόνο αντίγραφο που απέμεινε.
      // Μια δοκιμή που σκάει πάνω στην ίδια ζημιά δεν του την ακυρώνει.
      const corrupt = DatabaseFileProfile(
        kind: DatabaseFileKind.callLogger,
        userVersion: 60,
        contentIntegrity: DatabaseIntegrityStatus.corrupt,
        integrityDetail: 'database disk image is malformed',
      );
      final verdict = judgeBackupDatabase(
        corrupt,
        openTrial: const DatabaseOpenTrial.fails('δεν ανοίγει'),
      );
      expect(verdict.restorable, isTrue);
      expect(verdict.requiresConfirmation, isTrue);
    });

    test('αναποφάσιστη δοκιμή δεν εμποδίζει τίποτα', () async {
      final path = await currentSchemaDatabase();
      final verdict = judgeBackupDatabase(
        await profileDatabaseFile(path),
        openTrial: const DatabaseOpenTrial.inconclusive(),
      );
      expect(verdict.restorable, isTrue);
    });
  });
}
