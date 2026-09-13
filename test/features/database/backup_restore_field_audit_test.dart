// Έλεγχος πεδίου: αντίγραφα ασφαλείας & επαναφορά, άκρη-σε-άκρη.
//
// Δεν είναι τεστ μονάδας. Στήνει ΠΡΑΓΜΑΤΙΚΑ αρχεία στον δίσκο — βάσεις SQLite
// με διαφορετικά σχήματα, zip φτιαγμένα και χαλασμένα — και τα περνά από τις
// ίδιες ακριβώς συναρτήσεις που τρέχει η εφαρμογή όταν ο χρήστης πατά
// «Επαναφορά». Ό,τι γράφεται εδώ είναι παρατήρηση της πραγματικής
// συμπεριφοράς, όχι εικασία.
//
//   flutter test test/features/database/backup_restore_field_audit_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_integrity_probe.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/features/database/services/backup_zip_candidate_selection.dart';
import 'package:call_logger/features/database/services/backup_zip_inventory.dart';
import 'package:call_logger/features/database/services/backup_zip_manifest.dart';
import 'package:call_logger/features/database/services/backup_zip_staging.dart';
import 'package:call_logger/features/database/services/database_file_replacement.dart';
import 'package:call_logger/features/database/services/restore_database_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ───────────────────────── Κατασκευαστές βάσεων ─────────────────────────

/// Οι επτά πίνακες που κάνουν μια βάση «της Καταγραφής Κλήσεων».
const _coreTables = <String, String>{
  'calls': 'id INTEGER PRIMARY KEY, date TEXT, description TEXT',
  'users': 'id INTEGER PRIMARY KEY, name TEXT',
  'phones': 'id INTEGER PRIMARY KEY, number TEXT',
  'equipment': 'id INTEGER PRIMARY KEY, code_equipment TEXT, name TEXT',
  'departments': 'id INTEGER PRIMARY KEY, name TEXT',
  'categories': 'id INTEGER PRIMARY KEY, name TEXT',
  'tasks': 'id INTEGER PRIMARY KEY, title TEXT',
};

/// Βάση της Καταγραφής Κλήσεων με ελεγχόμενη έκδοση σχήματος και περιεχόμενο.
Future<void> makeCallLoggerDb(
  String path, {
  int version = 59,
  Iterable<String> omitTables = const [],
  int calls = 3,
}) async {
  final db = await databaseFactory.openDatabase(path);
  try {
    for (final entry in _coreTables.entries) {
      if (omitTables.contains(entry.key)) continue;
      await db.execute('CREATE TABLE ${entry.key} (${entry.value})');
    }
    if (!omitTables.contains('calls')) {
      for (var i = 0; i < calls; i++) {
        await db.insert('calls', {
          'date': '2026-09-${(i % 28) + 1}',
          'description': 'κλήση $i',
        });
      }
    }
    await db.execute('PRAGMA user_version = $version');
  } finally {
    await db.close();
  }
}

/// Βάση της Λάμπας: οι δικοί της πίνακες-υπογραφή.
Future<void> makeLampDb(String path, {int version = 12}) async {
  final db = await databaseFactory.openDatabase(path);
  try {
    await db.execute('CREATE TABLE owners (id INTEGER PRIMARY KEY, name TEXT)');
    await db.execute(
      'CREATE TABLE offices (id INTEGER PRIMARY KEY, name TEXT)',
    );
    await db.execute(
      'CREATE TABLE data_issues (id INTEGER PRIMARY KEY, kind TEXT)',
    );
    await db.execute(
      'CREATE TABLE equipment (id INTEGER PRIMARY KEY, '
      'code TEXT, name TEXT)',
    );
    await db.execute('PRAGMA user_version = $version');
  } finally {
    await db.close();
  }
}

/// Ανακατεμένο σχήμα: πίνακες Καταγραφής ΚΑΙ Λάμπας στο ίδιο αρχείο.
Future<void> makeHybridDb(String path) async {
  final db = await databaseFactory.openDatabase(path);
  try {
    await db.execute('CREATE TABLE calls (id INTEGER PRIMARY KEY, date TEXT)');
    await db.execute('CREATE TABLE owners (id INTEGER PRIMARY KEY, name TEXT)');
    await db.execute(
      'CREATE TABLE offices (id INTEGER PRIMARY KEY, name TEXT)',
    );
    await db.execute('PRAGMA user_version = 59');
  } finally {
    await db.close();
  }
}

/// Έγκυρο SQLite χωρίς κανέναν πίνακα χρήστη.
Future<void> makeEmptyDb(String path) async {
  final db = await databaseFactory.openDatabase(path);
  await db.close();
}

/// Έγκυρο SQLite με ξένο σχήμα (π.χ. βάση άλλου προγράμματος).
Future<void> makeForeignDb(String path) async {
  final db = await databaseFactory.openDatabase(path);
  try {
    await db.execute(
      'CREATE TABLE invoices (id INTEGER PRIMARY KEY, sum REAL)',
    );
    await db.execute('PRAGMA user_version = 7');
  } finally {
    await db.close();
  }
}

// ───────────────────────── Κατασκευαστές αντιγράφων ─────────────────────

/// Γράφει πραγματικό `.zip` από ονόματα εγγραφών σε bytes.
Future<void> writeZip(String zipPath, Map<String, List<int>> entries) async {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  await File(zipPath).writeAsBytes(ZipEncoder().encode(archive), flush: true);
}

List<int> manifestBytes({int? schemaVersion = 59, String? dbName}) {
  return utf8.encode(
    jsonEncode(<String, Object?>{
      'originalDatabasePath': r'F:\Data Base\call_logger.db',
      'databaseFileName': dbName ?? 'call_logger.db',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': '0.41.0',
      'schemaVersion': schemaVersion,
    }),
  );
}

// ───────────────────────── Καταγραφή ευρημάτων ──────────────────────────

final _log = <String>[];

void note(String scenario, String observed) {
  _log.add('  $scenario\n      → $observed');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('backup_audit_');
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } catch (_) {}
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('\n═══ ΙΧΝΟΣ ΠΑΡΑΤΗΡΗΣΕΩΝ ═══\n${_log.join('\n')}\n');
  });

  String at(String name) => p.join(root.path, name);

  // ═══════════════════ Β. Τι βλέπει μέσα στο αντίγραφο ═══════════════════

  group('Β. Απογραφή περιεχομένου αντιγράφου', () {
    test('Β1 · zip που δεν υπάρχει', () async {
      final inv = await inventoryBackupZip(at('φάντασμα.zip'));
      note(
        'Β1 ανύπαρκτο zip',
        'υποψήφιοι=${inv.eligibleCandidates.length}, '
            'προειδοποιήσεις=${inv.cleanupWarnings}',
      );
      expect(inv.eligibleCandidates, isEmpty);
      expect(inv.cleanupWarnings, isNotEmpty);
    });

    test('Β2 · αρχείο που δεν είναι zip', () async {
      final path = at('ψεύτικο.zip');
      await File(path).writeAsString('Αυτό δεν είναι zip, είναι κείμενο.');
      final inv = await inventoryBackupZip(path);
      note(
        'Β2 σκουπίδια με κατάληξη .zip',
        'υποψήφιοι=${inv.eligibleCandidates.length}, '
            'προειδοποιήσεις=${inv.cleanupWarnings.length}',
      );
      expect(inv.eligibleCandidates, isEmpty);
    });

    test('Β3 · zip κομμένο στη μέση', () async {
      final good = at('καλό.zip');
      final dbPath = at('πηγή.db');
      await makeCallLoggerDb(dbPath);
      await writeZip(good, {
        'call_logger.db': await File(dbPath).readAsBytes(),
        BackupZipManifest.zipEntryName: manifestBytes(),
      });
      final bytes = await File(good).readAsBytes();
      final truncated = at('κομμένο.zip');
      await File(truncated).writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));

      final inv = await inventoryBackupZip(truncated);
      note(
        'Β3 κομμένο zip',
        'υποψήφιοι=${inv.eligibleCandidates.length}, '
            'απορρίψεις=${inv.rejectedCandidates.length}, '
            'προειδοποιήσεις=${inv.cleanupWarnings.length}',
      );
      final decision = decideBackupZipCandidateSelection(inv);
      note('Β3 απόφαση', '${decision.kind} · ${decision.failureMessage}');
      expect(decision.kind, BackupZipCandidateSelectionKind.none);
    });

    test('Β4 · zip χωρίς κανένα .db', () async {
      final path = at('μόνο_εικόνες.zip');
      await writeZip(path, {
        'maps_images/ισόγειο.png': utf8.encode('PNG'),
        BackupZipManifest.zipEntryName: manifestBytes(),
      });
      final inv = await inventoryBackupZip(path);
      final decision = decideBackupZipCandidateSelection(inv);
      note('Β4 zip χωρίς βάση', decision.failureMessage ?? '—');
      expect(decision.kind, BackupZipCandidateSelectionKind.none);
    });

    test('Β5 · μία έγκυρη βάση → αυτόματη επιλογή', () async {
      final dbPath = at('πηγή.db');
      await makeCallLoggerDb(dbPath);
      final path = at('ένα.zip');
      await writeZip(path, {
        'call_logger.db': await File(dbPath).readAsBytes(),
        BackupZipManifest.zipEntryName: manifestBytes(),
      });
      final inv = await inventoryBackupZip(path);
      final decision = decideBackupZipCandidateSelection(inv);
      note(
        'Β5 μία βάση',
        '${decision.kind} · ${decision.selected?.displayName} · '
            'έκδοση=${decision.selected?.profile.userVersion}',
      );
      expect(decision.kind, BackupZipCandidateSelectionKind.automatic);
    });

    test('Β6 · δύο έγκυρες → υποχρεωτική ερώτηση', () async {
      final a = at('α.db');
      final b = at('β.db');
      await makeCallLoggerDb(a, calls: 2);
      await makeCallLoggerDb(b, calls: 9);
      final path = at('δύο.zip');
      await writeZip(path, {
        'call_logger.db': await File(a).readAsBytes(),
        'Hospital.db': await File(b).readAsBytes(),
        BackupZipManifest.zipEntryName: manifestBytes(),
      });
      final inv = await inventoryBackupZip(path);
      final decision = decideBackupZipCandidateSelection(inv);
      note('Β6 δύο βάσεις', '${decision.kind}');
      expect(decision.requiresUserChoice, isTrue);
    });

    test('Β7 · μόνο βάση Λάμπας μέσα', () async {
      final lamp = at('lampa.db');
      await makeLampDb(lamp);
      final path = at('μόνο_λάμπα.zip');
      await writeZip(path, {
        'lamp_db/lampa.db': await File(lamp).readAsBytes(),
        BackupZipManifest.zipEntryName: manifestBytes(),
      });
      final inv = await inventoryBackupZip(path);
      final decision = decideBackupZipCandidateSelection(inv);
      note('Β7 μόνο Λάμπα', decision.failureMessage ?? '—');
      expect(decision.kind, BackupZipCandidateSelectionKind.none);
    });

    test('Β8 · υβρίδιο, κενή, ξένη, ελλιπής — όλες μαζί', () async {
      final hybrid = at('υβρίδιο.db');
      final empty = at('κενή.db');
      final foreign = at('ξένη.db');
      final partial = at('λειψή.db');
      await makeHybridDb(hybrid);
      await makeEmptyDb(empty);
      await makeForeignDb(foreign);
      await makeCallLoggerDb(partial, omitTables: ['phones', 'departments']);

      final path = at('ανάμεικτο.zip');
      await writeZip(path, {
        'υβρίδιο.db': await File(hybrid).readAsBytes(),
        'κενή.db': await File(empty).readAsBytes(),
        'ξένη.db': await File(foreign).readAsBytes(),
        'λειψή.db': await File(partial).readAsBytes(),
        BackupZipManifest.zipEntryName: manifestBytes(),
      });
      final inv = await inventoryBackupZip(path);
      note(
        'Β8 απορρίψεις',
        inv.rejectedCandidates
            .map((r) => '${r.displayName}: ${r.reason}')
            .join(' | '),
      );
      note(
        'Β8 επιλέξιμοι με προειδοποίηση',
        inv.eligibleCandidates
            .map((c) => '${c.displayName}: ${c.checkWarning ?? "καθαρός"}')
            .join(' | '),
      );

      final decision = decideBackupZipCandidateSelection(inv);
      note('Β8 απόφαση', '${decision.kind}');

      // Η ελλιπής μένει ορατή αλλά σημασμένη — ο χρήστης πρέπει να δει ΓΙΑΤΙ.
      final incomplete = inv.eligibleCandidates
          .where((c) => c.displayName == 'λειψή.db')
          .toList();
      expect(incomplete, hasLength(1));
      expect(incomplete.single.checkFailed, isTrue);
      expect(
        judgeBackupDatabase(incomplete.single.profile).restorable,
        isFalse,
      );
    });

    test('Β9 · μηδενικού μεγέθους .db', () async {
      final zero = at('μηδέν.db');
      await File(zero).writeAsBytes(const []);
      final path = at('μηδενικό.zip');
      await writeZip(path, {
        'μηδέν.db': await File(zero).readAsBytes(),
        BackupZipManifest.zipEntryName: manifestBytes(),
      });
      final inv = await inventoryBackupZip(path);
      note(
        'Β9 άδειο αρχείο .db',
        'επιλέξιμοι=${inv.eligibleCandidates.map((c) => c.profile.kind).toList()} '
            'απορρίψεις=${inv.rejectedCandidates.map((r) => r.reason).toList()}',
      );
      final decision = decideBackupZipCandidateSelection(inv);
      note('Β9 απόφαση', '${decision.kind} · ${decision.failureMessage ?? ""}');
    });

    test('Β10 · «.db» που στην πραγματικότητα είναι κείμενο', () async {
      final path = at('κείμενο.zip');
      await writeZip(path, {
        'call_logger.db': utf8.encode('Καλημέρα, δεν είμαι βάση.'),
        BackupZipManifest.zipEntryName: manifestBytes(),
      });
      final inv = await inventoryBackupZip(path);
      note(
        'Β10 κείμενο μεταμφιεσμένο σε βάση',
        'επιλέξιμοι=${inv.eligibleCandidates.map((c) => "${c.profile.kind}/${c.checkFailed}").toList()} '
            'απορρίψεις=${inv.rejectedCandidates.map((r) => r.reason).toList()}',
      );
      final decision = decideBackupZipCandidateSelection(inv);
      note('Β10 απόφαση', '${decision.kind}');
      if (decision.selected != null) {
        note(
          'Β10 κρίση επαναφοράς',
          judgeBackupDatabase(decision.selected!.profile).reason ??
              'ΕΠΙΤΡΕΠΕΤΑΙ',
        );
      }
    });

    test('Β11 · αντίγραφο χωρίς manifest (παλιάς έκδοσης)', () async {
      final dbPath = at('πηγή.db');
      await makeCallLoggerDb(dbPath);
      final path = at('παλιό.zip');
      await writeZip(path, {
        'call_logger.db': await File(dbPath).readAsBytes(),
        'maps_images/ισόγειο.png': utf8.encode('PNG'),
      });
      final inv = await inventoryBackupZip(path);
      note(
        'Β11 χωρίς manifest',
        'πλήρες αντίγραφο=${inv.isFullBackupArchive}, '
            'κατόψεις=${inv.portablePresence.mapsCount}',
      );
      expect(inv.eligibleCandidates, hasLength(1));
    });

    test('Β12 · manifest με άκυρο JSON δεν ρίχνει τίποτα', () async {
      final dbPath = at('πηγή.db');
      await makeCallLoggerDb(dbPath);
      final path = at('σπασμένο_manifest.zip');
      await writeZip(path, {
        'call_logger.db': await File(dbPath).readAsBytes(),
        BackupZipManifest.zipEntryName: utf8.encode('{όχι json'),
      });
      final inv = await inventoryBackupZip(path);
      note(
        'Β12 άκυρο manifest',
        'επιλέξιμοι=${inv.eligibleCandidates.length}, '
            'πλήρες=${inv.isFullBackupArchive}',
      );
      expect(inv.eligibleCandidates, hasLength(1));
    });

    test('Β13 · πλήθη φορητών φτάνουν στον διάλογο', () async {
      final dbPath = at('πηγή.db');
      final lamp = at('lampa.db');
      await makeCallLoggerDb(dbPath);
      await makeLampDb(lamp);
      final path = at('πλήρες.zip');
      await writeZip(path, {
        'call_logger.db': await File(dbPath).readAsBytes(),
        BackupZipManifest.zipEntryName: manifestBytes(),
        'maps_images/ισόγειο.png': utf8.encode('A'),
        'maps_images/όροφος1.png': utf8.encode('B'),
        'images/εργαλείο.png': utf8.encode('C'),
        'dictionaries/core.txt': utf8.encode('λέξη'),
        'lamp_db/lampa.db': await File(lamp).readAsBytes(),
      });
      final inv = await inventoryBackupZip(path);
      final pp = inv.portablePresence;
      note(
        'Β13 πλήρες αντίγραφο',
        'πλήρες=${inv.isFullBackupArchive} κατόψεις=${pp.mapsCount} '
            'εικονίδια=${pp.imagesCount} λεξικό=${pp.dictionariesCount} '
            'λάμπα=${pp.lampDatabaseCount}',
      );
      expect(inv.isFullBackupArchive, isTrue);
      expect(pp.mapsCount, 2);
      expect(
        inv.eligibleCandidates,
        hasLength(1),
        reason: 'Η βάση Λάμπας δεν είναι υποψήφια για επαναφορά',
      );
    });
  });

  // ═══════════════════ Γ. Κρίση συμβατότητας έκδοσης ═════════════════════

  group('Γ. Συμβατότητα έκδοσης σχήματος', () {
    Future<DatabaseFileProfile> profileOf(int version) async {
      final path = at('έκδοση_$version.db');
      await makeCallLoggerDb(path, version: version);
      return profileDatabaseFile(path);
    }

    test('Γ1 · τρέχουσα έκδοση 59', () async {
      final v = judgeBackupDatabase(await profileOf(59));
      note('Γ1 v59', v.restorable ? 'ΕΠΙΤΡΕΠΕΤΑΙ' : 'ΜΠΛΟΚ: ${v.reason}');
      expect(v.restorable, isTrue);
    });

    test('Γ2 · παλαιότερη έκδοση 17', () async {
      final v = judgeBackupDatabase(await profileOf(17));
      note(
        'Γ2 v17 (παλιά)',
        v.restorable ? 'ΕΠΙΤΡΕΠΕΤΑΙ — αναβάθμιση από μεταπτώσεις' : 'ΜΠΛΟΚ',
      );
      expect(v.restorable, isTrue);
    });

    test('Γ3 · ΝΕΟΤΕΡΗ έκδοση 99 — τι λέει ο κριτής;', () async {
      final profile = await profileOf(99);
      final v = judgeBackupDatabase(profile);
      note(
        'Γ3 v99 (από το μέλλον)',
        'είδος=${profile.kind} έκδοση=${profile.userVersion} → '
            '${v.restorable ? "ΕΠΙΤΡΕΠΕΤΑΙ" : "ΜΠΛΟΚ: ${v.reason}"}',
      );
    });

    test('Γ4 · έκδοση 0 με πλήρες σχήμα', () async {
      final profile = await profileOf(0);
      final v = judgeBackupDatabase(profile);
      note(
        'Γ4 v0 με πλήρεις πίνακες',
        'είδος=${profile.kind} → '
            '${v.restorable ? "ΕΠΙΤΡΕΠΕΤΑΙ" : "ΜΠΛΟΚ: ${v.reason}"}',
      );
    });
  });

  // ═══════════════════ Δ. Αντικατάσταση & ανάκαμψη ═══════════════════════

  group('Δ. Αντικατάσταση αρχείου βάσης', () {
    test('Δ1 · υγιής στόχος φυλάσσεται πριν αντικατασταθεί', () async {
      final target = at('τρέχουσα.db');
      final source = at('αντίγραφο.db');
      await makeCallLoggerDb(target, calls: 5);
      await makeCallLoggerDb(source, calls: 40);

      final result = await DatabaseFileReplacement.replaceFromFile(
        targetDatabasePath: target,
        sourceDatabasePath: source,
      );
      note(
        'Δ1 υγιής στόχος',
        'επιτυχία=${result.success} φυλάχθηκε='
            '${result.preRestoreBackupPath == null ? "ΟΧΙ" : p.basename(result.preRestoreBackupPath!)}',
      );
      expect(result.success, isTrue);
      expect(result.preRestoreBackupPath, isNotNull);
      expect(File(result.preRestoreBackupPath!).existsSync(), isTrue);

      final after = await profileDatabaseFile(target);
      expect(after.callCount, 40, reason: 'Ο στόχος έχει πια το αντίγραφο');
      final saved = await profileDatabaseFile(result.preRestoreBackupPath!);
      expect(saved.callCount, 5, reason: 'Η παλιά βάση σώθηκε ακέραιη');
    });

    test(
      'Δ2 · κατεστραμμένος στόχος επιτρέπεται — είναι η αιτία επαναφοράς',
      () async {
        final target = at('χαλασμένη.db');
        final source = at('αντίγραφο.db');
        await File(target).writeAsString('σκουπίδια που δεν ανοίγουν');
        await makeCallLoggerDb(source, calls: 11);

        final result = await DatabaseFileReplacement.replaceFromFile(
          targetDatabasePath: target,
          sourceDatabasePath: source,
        );
        note(
          'Δ2 κατεστραμμένος στόχος',
          'επιτυχία=${result.success} ${result.message ?? ""}',
        );
        expect(result.success, isTrue);
      },
    );

    test('Δ3 · βάση Λάμπας ως στόχος απαγορεύεται', () async {
      final target = at('lampa.db');
      final source = at('αντίγραφο.db');
      await makeLampDb(target);
      await makeCallLoggerDb(source);

      final result = await DatabaseFileReplacement.replaceFromFile(
        targetDatabasePath: target,
        sourceDatabasePath: source,
      );
      note(
        'Δ3 στόχος = βάση Λάμπας',
        'επιτυχία=${result.success} · ${result.message ?? ""}',
      );
      expect(result.success, isFalse);

      final still = await profileDatabaseFile(target);
      expect(
        still.kind,
        DatabaseFileKind.lamp,
        reason: 'Η βάση Λάμπας έμεινε ανέγγιχτη',
      );
    });

    test('Δ4 · πηγή που εξαφανίστηκε', () async {
      final target = at('τρέχουσα.db');
      await makeCallLoggerDb(target, calls: 7);
      final result = await DatabaseFileReplacement.replaceFromFile(
        targetDatabasePath: target,
        sourceDatabasePath: at('δεν_υπάρχει.db'),
      );
      note(
        'Δ4 πηγή λείπει',
        'επιτυχία=${result.success} · ${result.message ?? ""}',
      );
      expect(result.success, isFalse);

      final still = await profileDatabaseFile(target);
      expect(still.callCount, 7, reason: 'Τίποτα δεν πειράχτηκε');
    });

    test('Δ5 · ο στόχος δεν υπάρχει καθόλου (νέο αρχείο)', () async {
      final target = at('νέα_θέση.db');
      final source = at('αντίγραφο.db');
      await makeCallLoggerDb(source, calls: 3);
      final result = await DatabaseFileReplacement.replaceFromFile(
        targetDatabasePath: target,
        sourceDatabasePath: source,
      );
      note(
        'Δ5 νέος προορισμός',
        'επιτυχία=${result.success} φύλαξη='
            '${result.preRestoreBackupPath ?? "καμία (σωστό)"}',
      );
      expect(result.success, isTrue);
      expect(result.preRestoreBackupPath, isNull);
    });
  });

  // ═══════════════════ Ε. Εξαγωγή από το αντίγραφο ═══════════════════════

  group('Ε. Εξαγωγή επιλεγμένης βάσης', () {
    test('Ε1 · η εξαγωγή δίνει προφίλ και διαδρομή', () async {
      final dbPath = at('πηγή.db');
      await makeCallLoggerDb(dbPath, calls: 21);
      final zip = at('αντίγραφο.zip');
      await writeZip(zip, {
        'call_logger.db': await File(dbPath).readAsBytes(),
        BackupZipManifest.zipEntryName: manifestBytes(),
      });

      final extraction = await extractSelectedBackupZipEntry(
        zip,
        databaseEntryName: 'call_logger.db',
        preferredOutputFileName: 'call_logger.db',
      );
      note(
        'Ε1 εξαγωγή',
        'επιτυχία=${extraction.success} είδος=${extraction.profile?.kind} '
            'κλήσεις=${extraction.profile?.callCount}',
      );
      expect(extraction.success, isTrue);
      expect(extraction.profile?.callCount, 21);
      if (extraction.extractedDatabasePath != null) {
        await cleanupStagedDatabase(extraction.extractedDatabasePath!);
      }
    });

    test(
      'Δ7 · η τελική αντικατάσταση αποτυγχάνει στο τελευταίο βήμα',
      () async {
        // Ο δίσκος γέμισε, ή κάποιος κλείδωσε το αρχείο τη στιγμή ακριβώς που
        // η νέα βάση επρόκειτο να πάρει τη θέση της παλιάς.
        final target = at('τρέχουσα.db');
        final source = at('αντίγραφο.db');
        await makeCallLoggerDb(target, calls: 12);
        await makeCallLoggerDb(source, calls: 99);

        final result = await DatabaseFileReplacement.replaceFromFile(
          targetDatabasePath: target,
          sourceDatabasePath: source,
          commitTempFile: (from, to) async =>
              throw const FileSystemException('ο δίσκος είναι γεμάτος'),
        );
        note(
          'Δ7 αποτυχία στο τελευταίο βήμα',
          '${result.success} · ${result.message}',
        );
        expect(result.success, isFalse);

        final survivor = await profileDatabaseFile(target);
        note(
          'Δ7 τι έμεινε στη θέση της βάσης',
          'είδος=${survivor.kind} κλήσεις=${survivor.callCount}',
        );
        expect(
          survivor.callCount,
          12,
          reason: 'Η παλιά βάση επέστρεψε στη θέση της, ακέραιη',
        );
      },
    );

    test(
      'Δ6 · δεύτερη επαναφορά την ίδια μέρα δεν σβήνει την πρώτη φύλαξη',
      () async {
        final target = at('τρέχουσα.db');
        final first = at('πρώτο.db');
        final second = at('δεύτερο.db');
        await makeCallLoggerDb(target, calls: 1);
        await makeCallLoggerDb(first, calls: 2);
        await makeCallLoggerDb(second, calls: 3);

        final a = await DatabaseFileReplacement.replaceFromFile(
          targetDatabasePath: target,
          sourceDatabasePath: first,
        );
        final b = await DatabaseFileReplacement.replaceFromFile(
          targetDatabasePath: target,
          sourceDatabasePath: second,
        );
        note(
          'Δ6 δύο επαναφορές την ίδια μέρα',
          '1η=${p.basename(a.preRestoreBackupPath ?? "-")} '
              '2η=${p.basename(b.preRestoreBackupPath ?? "-")}',
        );
        expect(a.preRestoreBackupPath, isNot(b.preRestoreBackupPath));
        expect(
          File(a.preRestoreBackupPath!).existsSync(),
          isTrue,
          reason: 'Η πρώτη φύλαξη επιβιώνει της δεύτερης επαναφοράς',
        );
        final oldest = await profileDatabaseFile(a.preRestoreBackupPath!);
        expect(oldest.callCount, 1);
      },
    );

    test('Ε2 · εξαγωγή εγγραφής που δεν υπάρχει στο zip', () async {
      final dbPath = at('πηγή.db');
      await makeCallLoggerDb(dbPath);
      final zip = at('αντίγραφο.zip');
      await writeZip(zip, {'call_logger.db': await File(dbPath).readAsBytes()});
      final extraction = await extractSelectedBackupZipEntry(
        zip,
        databaseEntryName: 'δεν_υπάρχει.db',
        preferredOutputFileName: 'δεν_υπάρχει.db',
      );
      note(
        'Ε2 λάθος εγγραφή',
        'επιτυχία=${extraction.success} · ${extraction.errorMessage ?? ""}',
      );
      expect(extraction.success, isFalse);
    });
  });

  // ═══════════════ Η. Αλλοιωμένο περιεχόμενο (bit rot) ═══════════════════
  //
  // Το σενάριο που φοβάται κανείς πραγματικά: το αρχείο ανοίγει, η κεφαλίδα
  // είναι σωστή, οι πίνακες απαντούν στο όνομά τους — αλλά σελίδες μέσα του
  // έχουν αλλοιωθεί από δίσκο που πεθαίνει ή από αντιγραφή που κόπηκε.

  group('Η. Βάση με αλλοιωμένο περιεχόμενο', () {
    /// Καίει bytes στη μέση του αρχείου, αφήνοντας άθικτη την κεφαλίδα.
    Future<void> corruptMiddle(String path) async {
      final bytes = await File(path).readAsBytes();
      final from = bytes.length ~/ 3;
      final to = (bytes.length * 2) ~/ 3;
      for (var i = from; i < to; i++) {
        bytes[i] = 0x00;
      }
      await File(path).writeAsBytes(bytes, flush: true);
    }

    test(
      'Η1 · αλλοιωμένη βάση αναγνωρίζεται, παρότι το σχήμα είναι άψογο',
      () async {
        final path = at('σάπια.db');
        await makeCallLoggerDb(path, calls: 400);
        await corruptMiddle(path);

        final profile = await profileDatabaseFile(path);
        final verdict = judgeBackupDatabase(profile);
        note(
          'Η1 αλλοιωμένη βάση',
          'είδος=${profile.kind} ακεραιότητα=${profile.contentIntegrity} → '
              '${verdict.requiresConfirmation ? "ΘΕΛΕΙ ΕΠΙΒΕΒΑΙΩΣΗ" : (verdict.restorable ? "ΕΠΙΤΡΕΠΕΤΑΙ" : "ΜΠΛΟΚ")}',
        );

        expect(
          profile.kind,
          DatabaseFileKind.callLogger,
          reason: 'Οι επτά πίνακες είναι όλοι εκεί — γι αυτό ξέφευγε',
        );
        expect(profile.contentIsCorrupt, isTrue);
        expect(
          verdict.requiresConfirmation,
          isTrue,
          reason: 'Δεν επαναφέρεται πια σιωπηλά',
        );
        expect(verdict.technicalDetail, isNotNull);
      },
    );

    test(
      'Η2 · αλλοιωμένη βάση μέσα σε αντίγραφο — φτάνει ως τον χρήστη;',
      () async {
        final dbPath = at('σάπια.db');
        await makeCallLoggerDb(dbPath, calls: 400);
        await corruptMiddle(dbPath);
        final zip = at('σάπιο_αντίγραφο.zip');
        await writeZip(zip, {
          'call_logger.db': await File(dbPath).readAsBytes(),
          BackupZipManifest.zipEntryName: manifestBytes(),
        });

        final inv = await inventoryBackupZip(zip);
        final decision = decideBackupZipCandidateSelection(inv);
        note('Η2 απογραφή αλλοιωμένου', 'απόφαση=${decision.kind}');

        // Η απογραφή προφιλάρει το ίδιο αρχείο με την ίδια συνάρτηση, άρα η
        // φθορά ταξιδεύει μαζί του ως τον διάλογο — χωρίς δεύτερο έλεγχο.
        expect(decision.selected, isNotNull);
        final v = judgeBackupDatabase(decision.selected!.profile);
        note(
          'Η2 κρίση',
          v.requiresConfirmation ? 'ΘΕΛΕΙ ΕΠΙΒΕΒΑΙΩΣΗ' : 'ΠΕΡΝΑ ΣΙΩΠΗΛΑ',
        );
        expect(v.requiresConfirmation, isTrue);
      },
    );

    test('Η4 · ο ξεχωριστός ανιχνευτής και ο ταξινομητής συμφωνούν', () async {
      // Δύο είσοδοι στον ίδιο έλεγχο: το χειροκίνητο διαγνωστικό πρόσβασης
      // ανοίγει δικό του αρχείο, ο ταξινομητής ρωτά την ήδη ανοιχτή σύνδεση.
      // Αν αποκλίνουν, ο χρήστης παίρνει δύο διαφορετικές απαντήσεις για το
      // ίδιο αρχείο ανάλογα με το πού πάτησε.
      final path = at('σάπια.db');
      await makeCallLoggerDb(path, calls: 400);
      await corruptMiddle(path);

      final sw = Stopwatch()..start();
      final probe = await runDatabaseIntegrityProbe(path);
      sw.stop();
      final profile = await profileDatabaseFile(path);

      note(
        'Η4 δύο είσοδοι',
        'ανιχνευτής=${probe.status} (${sw.elapsedMilliseconds}ms) · '
            'ταξινομητής=${profile.contentIntegrity}',
      );
      expect(profile.contentIntegrity, probe.status);
    });

    test('Η5 · η υγιής βάση δεν κατηγορείται', () async {
      final path = at('υγιής.db');
      await makeCallLoggerDb(path, calls: 400);
      final profile = await profileDatabaseFile(path);
      note('Η5 υγιής βάση', 'ακεραιότητα=${profile.contentIntegrity}');
      expect(profile.contentIsCorrupt, isFalse);
      expect(judgeBackupDatabase(profile).requiresConfirmation, isFalse);
    });

    test('Η3 · μόνο η κεφαλίδα SQLite, τίποτα άλλο', () async {
      final path = at('μόνο_κεφαλίδα.db');
      final header = <int>[
        ...'SQLite format 3'.codeUnits,
        0,
        ...List<int>.filled(84, 0),
      ];
      await File(path).writeAsBytes(header, flush: true);
      final profile = await profileDatabaseFile(path);
      final verdict = judgeBackupDatabase(profile);
      note(
        'Η3 σκέτη κεφαλίδα',
        'είδος=${profile.kind} → '
            '${verdict.restorable ? "ΕΠΙΤΡΕΠΕΤΑΙ" : "ΜΠΛΟΚ: ${verdict.reason}"}',
      );
      expect(verdict.restorable, isFalse);
    });
  });

  // ═══════════ Ζ. Τι γίνεται ΜΕΤΑ την επαναφορά: το άνοιγμα ══════════════
  //
  // Ο κριτής της επαναφοράς λέει «ναι». Το ερώτημα εδώ είναι αν η βάση που
  // μόλις κάθισε στη θέση της τρέχουσας ανοίγει πράγματι — με τον ίδιο
  // ακριβώς τρόπο που την ανοίγει η εφαρμογή μετά την εναλλαγή.

  group('Ζ. Άνοιγμα της βάσης που επαναφέρθηκε', () {
    Future<String> openLikeTheApp(String path) async {
      try {
        final db = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: kDatabaseSchemaVersion,
            onCreate: onDatabaseCreate,
            onUpgrade: onDatabaseUpgradeSquashed,
            onDowngrade: onDatabaseDowngradeSquashed,
          ),
        );
        final v = await db.rawQuery('PRAGMA user_version');
        final after = v.first['user_version'];
        await db.close();
        return 'ΑΝΟΙΞΕ · έκδοση μετά=$after';
      } catch (e) {
        final text = '$e';
        return 'ΕΣΚΑΣΕ · ${text.length > 160 ? text.substring(0, 160) : text}';
      }
    }

    test('Ζ1 · έκδοση 59 ανοίγει κανονικά', () async {
      final path = at('v59.db');
      await makeCallLoggerDb(path, version: kDatabaseSchemaVersion);
      note('Ζ1 v59', await openLikeTheApp(path));
    });

    test('Ζ2 · έκδοση 0 με πλήρες σχήμα — ο κριτής την πέρασε', () async {
      final path = at('v0.db');
      await makeCallLoggerDb(path, version: 0);
      expect(
        judgeBackupDatabase(await profileDatabaseFile(path)).restorable,
        isTrue,
        reason: 'Ο κριτής της επαναφοράς την επιτρέπει — τι λέει το άνοιγμα;',
      );
      note('Ζ2 v0 μετά την επαναφορά', await openLikeTheApp(path));
    });

    // Το σχήμα ΠΡΑΓΜΑΤΙΚΗΣ βάσης της εφαρμογής, με χειροκίνητα γυρισμένο
    // αριθμό έκδοσης: έτσι δοκιμάζονται οι ίδιες οι μεταπτώσεις, όχι μια
    // αυτοσχέδια κατασκευή που δεν υπήρξε ποτέ σε υπολογιστή χρήστη.
    Future<void> makeRealSchemaDb(String path, {required int stamp}) async {
      final db = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: kDatabaseSchemaVersion,
          onCreate: onDatabaseCreate,
          onUpgrade: onDatabaseUpgradeSquashed,
        ),
      );
      await db.execute('PRAGMA user_version = $stamp');
      await db.close();
    }

    test('Ζ4 · πραγματικό σχήμα με ετικέτα έκδοσης 17 — αντέχουν οι '
        'μεταπτώσεις να ξανατρέξουν;', () async {
      final path = at('πραγματική_v17.db');
      await makeRealSchemaDb(path, stamp: 17);
      note('Ζ4 πραγματικό σχήμα, ετικέτα v17', await openLikeTheApp(path));
    });

    test('Ζ5 · πραγματικό σχήμα με ετικέτα έκδοσης 58', () async {
      final path = at('πραγματική_v58.db');
      await makeRealSchemaDb(path, stamp: kDatabaseSchemaVersion - 1);
      note('Ζ5 πραγματικό σχήμα, ετικέτα v58', await openLikeTheApp(path));
    });

    test('Ζ6 · οι 7 πίνακες υπάρχουν αλλά το σχήμα δεν είναι της έκδοσης '
        'που δηλώνει', () async {
      // Το ρεαλιστικό «αρχείο από αλλού»: κάποιος έφτιαξε πίνακες με τα σωστά
      // ονόματα (εξαγωγή από εργαλείο, χειροκίνητη επισκευή) και το αρχείο
      // δηλώνει μια έκδοση που δεν αντιστοιχεί στο περιεχόμενό του.
      final path = at('ψεύτικη_v17.db');
      await makeCallLoggerDb(path, version: 17);
      final verdict = judgeBackupDatabase(await profileDatabaseFile(path));
      note(
        'Ζ6 κρίση επαναφοράς',
        verdict.restorable ? 'ΕΠΙΤΡΕΠΕΤΑΙ' : 'ΜΠΛΟΚ: ${verdict.reason}',
      );
      note('Ζ6 άνοιγμα μετά την επαναφορά', await openLikeTheApp(path));
    });

    test('Ζ3 · έκδοση 99 από το μέλλον — ο κριτής την πέρασε', () async {
      final path = at('v99.db');
      await makeCallLoggerDb(path, version: 99);
      expect(
        judgeBackupDatabase(await profileDatabaseFile(path)).restorable,
        isTrue,
        reason: 'Ο κριτής της επαναφοράς την επιτρέπει — τι λέει το άνοιγμα;',
      );
      note('Ζ3 v99 μετά την επαναφορά', await openLikeTheApp(path));
    });
  });
}
