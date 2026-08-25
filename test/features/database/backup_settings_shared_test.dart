// Φάση 2 του μηχανισμού αντιγράφων: το «δέμα» των ρυθμίσεων είναι **μία κοινή
// ρύθμιση της βάσης** — ο διαχειριστής την ορίζει, όλοι τη βλέπουν, όποιος
// έχει το δικαίωμα την εκτελεί απαράλλαχτη. Η πύλη ActiveBackupSettings κάνει
// τη μετάπτωση της επιστροφής (προσωπικό → κοινό) μία φορά ανά βάση.
// Εδώ ζουν και οι έλεγχοι του δικαιώματος πλήρους αντιγράφου και της
// εξαγωγής/επαναφοράς προσωπικών ρυθμίσεων (καρτέλα «Αντίγραφα»).
//
//   flutter test test/features/database/backup_settings_shared_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_settings_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/permission_service.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/providers/database_backup_settings_provider.dart';
import 'package:call_logger/features/database/services/active_backup_settings.dart';
import 'package:call_logger/features/database/services/database_maintenance_service.dart';
import 'package:call_logger/features/database/services/database_stats_service.dart';
import 'package:call_logger/features/operators/services/profile_settings_export.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../test_setup.dart';

Operator _operator(int id, {bool isAdmin = false}) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  isAdmin: isAdmin,
  createdAt: DateTime(2026, 8, 20),
);

String _bundleWithFolder(String folder) => DatabaseBackupSettings.defaults()
    .copyWith(destinationDirectory: folder)
    .toJsonString();

Future<void> _insertOperatorRow(int id, {bool isAdmin = false}) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('operators', {
    'id': id,
    'display_name': 'Χρήστης $id',
    'is_admin': isAdmin ? 1 : 0,
    'is_active': 1,
    'created_at': '2026-08-20T00:00:00.000',
  });
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUp(() async {
    CurrentOperator.reset();
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: [
        DatabaseBackupSettings.appSettingsKey,
        ActiveBackupSettings.migrationMarkerKey,
      ],
    );
    await db.delete(OperatorSettingsRepository.tableName);
    await db.delete('operators');
  });

  tearDown(CurrentOperator.reset);

  group('Το δέμα είναι κοινό (Φάση 2)', () {
    test('το κλειδί παραμένει το ιστορικό κοινό — παλιές εκδόσεις το διαβάζουν', () {
      expect(
        DatabaseBackupSettings.appSettingsKey,
        'database_backup_settings_v1',
      );
    });

    test('η αλλαγή του διαχειριστή φαίνεται σε όλους', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(databaseBackupSettingsProvider.notifier);

      CurrentOperator.activate(_operator(901, isAdmin: true));
      await notifier.load();
      await notifier.setDestinationDirectory(r'D:\koinos_fakelos');

      CurrentOperator.activate(_operator(902));
      await notifier.load();
      expect(
        container.read(databaseBackupSettingsProvider).destinationDirectory,
        r'D:\koinos_fakelos',
        reason: 'Ένα δέμα για όλους — όχι δικό του αντίτυπο ανά χρήστη.',
      );

      CurrentOperator.reset();
      final anonymous = await ActiveBackupSettings.read();
      expect(anonymous.destinationDirectory, r'D:\koinos_fakelos');
    });

    test('read/write της πύλης δουλεύουν στην κοινή θέση', () async {
      final db = await DatabaseHelper.instance.database;
      CurrentOperator.activate(_operator(903, isAdmin: true));

      await ActiveBackupSettings.overwriteAll(
        DatabaseBackupSettings.defaults().copyWith(
          destinationDirectory: r'D:\apo_thn_pylh',
        ),
      );

      final raw = await SettingsRepository(
        db,
      ).getSetting(DatabaseBackupSettings.appSettingsKey);
      expect(raw, contains('apo_thn_pylh'));
      expect(
        await OperatorSettingsRepository(
          db,
        ).getValue(903, DatabaseBackupSettings.appSettingsKey),
        isNull,
        reason: 'Καμία προσωπική εγγραφή — το κλειδί δεν είναι πια προσωπικό.',
      );
    });
  });

  group('Μετάπτωση: επιστροφή του δέματος στα κοινά', () {
    test(
      'το προσωπικό δέμα του διαχειριστή προωθείται στα κοινά, μία φορά',
      () async {
        final db = await DatabaseHelper.instance.database;
        await _insertOperatorRow(71, isAdmin: true);
        await _insertOperatorRow(72);

        // Παγωμένη κοινή τιμή + φρέσκο προσωπικό αντίτυπο διαχειριστή +
        // αδέσποτο αντίτυπο απλού χρήστη.
        await SettingsRepository(db).saveSetting(
          DatabaseBackupSettings.appSettingsKey,
          _bundleWithFolder(r'D:\pagomenos'),
        );
        final opSettings = OperatorSettingsRepository(db);
        await opSettings.setValue(
          71,
          DatabaseBackupSettings.appSettingsKey,
          _bundleWithFolder(r'D:\freskos_tou_diaxeiristi'),
        );
        await opSettings.setValue(
          72,
          DatabaseBackupSettings.appSettingsKey,
          _bundleWithFolder(r'D:\adespoto'),
        );

        CurrentOperator.activate(_operator(71, isAdmin: true));
        final settings = await ActiveBackupSettings.read();

        expect(settings.destinationDirectory, r'D:\freskos_tou_diaxeiristi');
        final shared = await SettingsRepository(
          db,
        ).getSetting(DatabaseBackupSettings.appSettingsKey);
        expect(shared, contains('freskos_tou_diaxeiristi'));
        expect(
          await opSettings.getValuesForKey(
            DatabaseBackupSettings.appSettingsKey,
          ),
          isEmpty,
          reason: 'Τα προσωπικά αντίτυπα καθαρίζονται — νεκρό βάρος.',
        );
        expect(
          await SettingsRepository(
            db,
          ).getSetting(ActiveBackupSettings.migrationMarkerKey),
          isNotNull,
        );
      },
    );

    test(
      'μετά τη σημαία, νέο προσωπικό αντίτυπο αγνοείται — δεν ξαναπροωθείται',
      () async {
        final db = await DatabaseHelper.instance.database;
        await _insertOperatorRow(71, isAdmin: true);

        // Πρώτη ανάγνωση: γράφει τη σημαία.
        await SettingsRepository(db).saveSetting(
          DatabaseBackupSettings.appSettingsKey,
          _bundleWithFolder(r'D:\freskia_koini'),
        );
        CurrentOperator.activate(_operator(71, isAdmin: true));
        await ActiveBackupSettings.read();

        // Παλιά έκδοση σε άλλο μηχάνημα ξαναγράφει προσωπικό αντίτυπο — αν
        // προωθούνταν, θα πατούσε τη φρέσκια κοινή τιμή με μπαγιάτικη.
        await OperatorSettingsRepository(db).setValue(
          71,
          DatabaseBackupSettings.appSettingsKey,
          _bundleWithFolder(r'D:\mpagiatiko'),
        );

        final settings = await ActiveBackupSettings.read();
        expect(settings.destinationDirectory, r'D:\freskia_koini');
      },
    );

    test(
      'αντίτυπο χωρίς δικαίωμα δεν προωθείται — μόνο καθαρίζεται',
      () async {
        final db = await DatabaseHelper.instance.database;
        await _insertOperatorRow(72);

        await SettingsRepository(db).saveSetting(
          DatabaseBackupSettings.appSettingsKey,
          _bundleWithFolder(r'D:\koini_alithia'),
        );
        final opSettings = OperatorSettingsRepository(db);
        await opSettings.setValue(
          72,
          DatabaseBackupSettings.appSettingsKey,
          _bundleWithFolder(r'D:\anexousiodotito'),
        );

        final settings = await ActiveBackupSettings.read();
        expect(settings.destinationDirectory, r'D:\koini_alithia');
        expect(
          await opSettings.getValuesForKey(
            DatabaseBackupSettings.appSettingsKey,
          ),
          isEmpty,
        );
      },
    );
  });

  group('Ατομική δέσμευση της κοινής ρύθμισης (Φάση 4)', () {
    test('κερδίζει όποιος βρει το αναμενόμενο ωμό JSON — ο δεύτερος όχι', () async {
      final db = await DatabaseHelper.instance.database;
      await SettingsRepository(db).saveSetting(
        DatabaseBackupSettings.appSettingsKey,
        _bundleWithFolder(r'D:\arxiki'),
      );

      final gate = await ActiveBackupSettings.readWithRaw();
      final claimA = gate.settings.copyWith(
        lastBackupAttempt: DateTime(2026, 8, 24, 12, 0),
      );
      expect(
        await ActiveBackupSettings.tryReplace(
          expectedRaw: gate.raw,
          replacement: claimA,
        ),
        isTrue,
      );

      // Δεύτερος διεκδικητής με το ΠΑΛΙΟ αναμενόμενο: χάνει και δεν πατά
      // την τιμή του πρώτου.
      final claimB = gate.settings.copyWith(
        lastBackupAttempt: DateTime(2026, 8, 24, 12, 0, 30),
      );
      expect(
        await ActiveBackupSettings.tryReplace(
          expectedRaw: gate.raw,
          replacement: claimB,
        ),
        isFalse,
      );
      final saved = await ActiveBackupSettings.read();
      expect(saved.lastBackupAttempt, DateTime(2026, 8, 24, 12, 0));
    });

    test('χωρίς αποθηκευμένη γραμμή: null-αναμενόμενο εισάγει μία φορά', () async {
      // Το setUp έχει σβήσει το κλειδί — αλλά η readWithRaw γράφει τη σημαία
      // μετάπτωσης ΧΩΡΙΣ να αγγίζει το δέμα, οπότε το raw μένει null.
      final gate = await ActiveBackupSettings.readWithRaw();
      expect(gate.raw, isNull);

      final first = gate.settings.copyWith(destinationDirectory: r'D:\a');
      expect(
        await ActiveBackupSettings.tryReplace(
          expectedRaw: null,
          replacement: first,
        ),
        isTrue,
      );
      expect(
        await ActiveBackupSettings.tryReplace(
          expectedRaw: null,
          replacement: gate.settings.copyWith(destinationDirectory: r'D:\b'),
        ),
        isFalse,
        reason: 'Η γραμμή υπάρχει πια — το null-αναμενόμενο δεν ξαναπερνά.',
      );
      expect((await ActiveBackupSettings.read()).destinationDirectory, r'D:\a');
    });

    test('JSON παλιάς έκδοσης: η δέσμευση συγκρίνει το ΩΜΟ κείμενο', () async {
      final db = await DatabaseHelper.instance.database;
      // Αποθηκευμένο από παλιά έκδοση: με νεκρά πεδία — δεν κάνει roundtrip
      // χαρακτήρα-χαρακτήρα μέσα από το μοντέλο.
      const legacyRaw =
          '{"destinationDirectory":"D:\\\\palia","backupOnExit":true,'
          '"backupDays":[6],"backupTime":"18:42","interval":1}';
      await SettingsRepository(
        db,
      ).saveSetting(DatabaseBackupSettings.appSettingsKey, legacyRaw);

      final gate = await ActiveBackupSettings.readWithRaw();
      expect(gate.raw, legacyRaw);
      expect(
        await ActiveBackupSettings.tryReplace(
          expectedRaw: gate.raw,
          replacement: gate.settings.copyWith(
            lastBackupAttempt: DateTime(2026, 8, 24, 12, 0),
          ),
        ),
        isTrue,
        reason:
            'Σύγκριση σε ξαναγραμμένη μορφή θα αποτύγχανε για πάντα σε '
            'δέμα γραμμένο από παλιά έκδοση.',
      );
    });
  });

  group('Δικαίωμα πλήρους αντιγράφου (Φάση 2 προφίλ)', () {
    test('ο απλός χρήστης ΔΕΝ το έχει από προεπιλογή', () {
      CurrentOperator.activate(_operator(931));
      expect(PermissionService.instance.can(AppPermission.fullBackup), isFalse);
    });

    test('ο διαχειριστής το έχει πάντα', () {
      CurrentOperator.activate(_operator(932, isAdmin: true));
      expect(PermissionService.instance.can(AppPermission.fullBackup), isTrue);
    });

    test(
      'χωρίς συνδεδεμένο χρήστη επιτρέπεται — ζώνη ασφαλείας, όχι κλειδαριά',
      () {
        CurrentOperator.reset();
        expect(
          PermissionService.instance.can(AppPermission.fullBackup),
          isTrue,
        );
      },
    );

    test('ρητό τικ του διαχειριστή το ξεκλειδώνει για απλό χρήστη', () {
      final trusted = Operator(
        id: 933,
        displayName: 'Έμπιστος',
        permissionOverrides: const {'full_backup': true},
        createdAt: DateTime(2026, 8, 20),
      );
      expect(
        PermissionService.instance.can(
          AppPermission.fullBackup,
          operator: trusted,
        ),
        isTrue,
      );
    });
  });

  group('Μία πύλη για τους καταναλωτές των ρυθμίσεων', () {
    Future<String> makeDest(String name) async {
      final dir = Directory.systemTemp.createTempSync(name);
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir.path;
    }

    Future<List<File>> backupFilesIn(String dest) async {
      final dir = Directory(dest);
      if (!dir.existsSync()) return const [];
      return dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db') || f.path.endsWith('.zip'))
          .toList();
    }

    DatabaseBackupSettings enabledBundle(String dest) =>
        DatabaseBackupSettings.defaults().copyWith(
          destinationDirectory: dest,
          backupOnExit: true,
        );

    test(
      'το αντίγραφο πριν από συντήρηση ακολουθεί το κοινό δέμα',
      () async {
        final dest = await makeDest('maint_shared_');
        final db = await DatabaseHelper.instance.database;
        await SettingsRepository(db).saveSetting(
          DatabaseBackupSettings.appSettingsKey,
          enabledBundle(dest).toJsonString(),
        );
        CurrentOperator.activate(_operator(962, isAdmin: true));

        final result = await DatabaseMaintenanceService()
            .runPreMaintenanceBackup();

        expect(result.kind, MaintenanceBackupPrecheck.ok);
        expect(await backupFilesIn(dest), hasLength(1));
      },
    );

    test(
      'τα Στατιστικά βρίσκουν το «τελευταίο αντίγραφο» στον κοινό φάκελο',
      () async {
        final dest = await makeDest('stats_shared_');
        final db = await DatabaseHelper.instance.database;
        final baseName = p.basenameWithoutExtension(db.path);
        File(
          p.join(dest, '2026-08-20_10-00_$baseName.db'),
        ).writeAsStringSync('x');

        await SettingsRepository(db).saveSetting(
          DatabaseBackupSettings.appSettingsKey,
          enabledBundle(dest).toJsonString(),
        );
        CurrentOperator.activate(_operator(963));

        final stats = await DatabaseStatsService.getDatabaseStats();
        expect(
          stats.lastBackupTime,
          isNotNull,
          reason: 'Η κάρτα διαβάζει το κοινό δέμα — ό,τι βλέπουν όλοι.',
        );
      },
    );
  });

  group('«Αντίγραφο των ρυθμίσεών μου» — εξαγωγή προφίλ', () {
    test('γράφει τις προσωπικές ρυθμίσεις του χρήστη σε JSON', () async {
      final db = await DatabaseHelper.instance.database;
      CurrentOperator.activate(_operator(941));
      await OperatorSettingsRepository(db).setValue(941, 'kleidi', 'timi');

      final dir = Directory.systemTemp.createTempSync('profile_export_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = p.join(dir.path, 'profil.json');

      final result = await exportActiveOperatorSettings(
        pickSavePath: (suggested) async {
          expect(suggested, contains('Χρήστης 941'));
          return target;
        },
        now: DateTime(2026, 8, 20, 12, 0),
      );

      expect(result.isSaved, isTrue);
      final payload =
          jsonDecode(File(target).readAsStringSync()) as Map<String, dynamic>;
      expect(payload['user'], 'Χρήστης 941');
      expect(payload['settings'], {'kleidi': 'timi'});
    });

    test('η ακύρωση του επιλογέα δεν γράφει τίποτα', () async {
      CurrentOperator.activate(_operator(942));
      final result = await exportActiveOperatorSettings(
        pickSavePath: (_) async => null,
      );
      expect(result.isSaved, isFalse);
      expect(result.error, isNull);
    });

    test('χωρίς συνδεδεμένο χρήστη εξηγεί γιατί δεν γίνεται', () async {
      CurrentOperator.reset();
      final result = await exportActiveOperatorSettings(
        pickSavePath: (_) async => 'δεν_θα_κληθεί.json',
      );
      expect(result.isSaved, isFalse);
      expect(result.error, contains('συνδεδεμένος χρήστης'));
    });
  });

  group('«Επαναφορά ρυθμίσεων» — εισαγωγή προφίλ', () {
    Future<String> writeExport(
      Directory dir,
      Map<String, dynamic> settings, {
      String user = 'Κάποιος',
    }) async {
      final path = p.join(dir.path, 'export.json');
      File(path).writeAsStringSync(
        jsonEncode({
          'user': user,
          'exported_at': '2026-08-20T12:00:00.000',
          'settings': settings,
        }),
      );
      return path;
    }

    test('επαναφέρει στο προφίλ ΤΟΥ ΣΥΝΔΕΔΕΜΕΝΟΥ, όχι του αρχείου', () async {
      final db = await DatabaseHelper.instance.database;
      final dir = Directory.systemTemp.createTempSync('profile_import_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = await writeExport(dir, {
        'show_lamp_nav': 'false',
      }, user: 'Άλλος');

      CurrentOperator.activate(_operator(951));
      final result = await importActiveOperatorSettings(
        pickOpenPath: () async => file,
      );

      expect(result.isRestored, isTrue);
      expect(result.restoredCount, 1);
      expect(
        await OperatorSettingsRepository(db).getValue(951, 'show_lamp_nav'),
        'false',
      );
    });

    test('αγνοεί κλειδιά που η έκδοση δεν αναγνωρίζει', () async {
      final db = await DatabaseHelper.instance.database;
      final dir = Directory.systemTemp.createTempSync('profile_import_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = await writeExport(dir, {
        'show_lamp_nav': 'false',
        'kleidi_apo_allh_ekdosh': 'τιμή',
      });

      CurrentOperator.activate(_operator(952));
      final result = await importActiveOperatorSettings(
        pickOpenPath: () async => file,
      );

      expect(result.restoredCount, 1, reason: 'Μόνο το γνωστό κλειδί.');
      expect(
        await OperatorSettingsRepository(
          db,
        ).getValue(952, 'kleidi_apo_allh_ekdosh'),
        isNull,
      );
    });

    test(
      'το δέμα των αντιγράφων ΔΕΝ επαναφέρεται πια από παλιά εξαγωγή — '
      'είναι κοινή ρύθμιση, όχι προσωπική',
      () async {
        final db = await DatabaseHelper.instance.database;
        final dir = Directory.systemTemp.createTempSync('profile_import_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = await writeExport(dir, {
          DatabaseBackupSettings.appSettingsKey: _bundleWithFolder(
            r'D:\apo_palia_exagogi',
          ),
        });

        CurrentOperator.activate(_operator(953));
        final result = await importActiveOperatorSettings(
          pickOpenPath: () async => file,
        );

        expect(result.restoredCount, 0);
        expect(
          await OperatorSettingsRepository(
            db,
          ).getValue(953, DatabaseBackupSettings.appSettingsKey),
          isNull,
        );
      },
    );

    test('χαλασμένο αρχείο εξηγεί το πρόβλημα, δεν σκάει', () async {
      final dir = Directory.systemTemp.createTempSync('profile_import_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = p.join(dir.path, 'bad.json');
      File(bad).writeAsStringSync('δεν είναι json');

      CurrentOperator.activate(_operator(954));
      final result = await importActiveOperatorSettings(
        pickOpenPath: () async => bad,
      );

      expect(result.isRestored, isFalse);
      expect(result.error, isNotNull);
    });

    test('ακύρωση: τίποτα δεν αλλάζει', () async {
      CurrentOperator.activate(_operator(955));
      final result = await importActiveOperatorSettings(
        pickOpenPath: () async => null,
      );
      expect(result.isRestored, isFalse);
      expect(result.error, isNull);
    });
  });
}
