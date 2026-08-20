// Φάση 2 — Πακέτο Β: το «δέμα» των αντιγράφων ασφαλείας είναι προσωπικό.
// Κάθε χρήστης έχει δικό του πρόγραμμα/φάκελο/κατάσταση· ο διαχειριστής
// κληρονομεί μία φορά τη σημερινή κοινή τιμή· χωρίς συνδεδεμένο χρήστη όλα
// δουλεύουν όπως χθες· η «Αλλαγή χρήστη» ξαναφορτώνει το δέμα μόνη της· και
// το πλήρες αντίγραφο είναι πλέον δικαίωμα μόνο του διαχειριστή.
//
//   flutter test test/features/database/backup_settings_per_operator_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_settings_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/permission_service.dart';
import 'package:call_logger/core/services/profile_settings.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/providers/database_backup_settings_provider.dart';
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

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUp(() async {
    CurrentOperator.reset();
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: [DatabaseBackupSettings.appSettingsKey],
    );
    await db.delete(OperatorSettingsRepository.tableName);
  });

  tearDown(CurrentOperator.reset);

  test('το κλειδί προφίλ ταυτίζεται με το παλιό κοινό κλειδί', () {
    expect(
      ProfileSettingKeys.databaseBackupSettings.key,
      DatabaseBackupSettings.appSettingsKey,
    );
  });

  test('χωρίς συνδεδεμένο χρήστη, φόρτωση και αποθήκευση όπως χθες', () async {
    final db = await DatabaseHelper.instance.database;
    await SettingsRepository(db).saveSetting(
      DatabaseBackupSettings.appSettingsKey,
      _bundleWithFolder(r'D:\koino'),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(databaseBackupSettingsProvider.notifier);

    await notifier.load();
    expect(
      container.read(databaseBackupSettingsProvider).destinationDirectory,
      r'D:\koino',
    );

    await notifier.setDestinationDirectory(r'D:\allo');
    final raw = await SettingsRepository(
      db,
    ).getSetting(DatabaseBackupSettings.appSettingsKey);
    expect(raw, contains('allo'));
  });

  test('κάθε χρήστης έχει το δικό του δέμα — πλήρως ανεξάρτητο', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(databaseBackupSettingsProvider.notifier);

    CurrentOperator.activate(_operator(901));
    await notifier.load();
    await notifier.setDestinationDirectory(r'D:\tou_prwtou');

    CurrentOperator.activate(_operator(902));
    await notifier.load();
    expect(
      container.read(databaseBackupSettingsProvider).destinationDirectory,
      isEmpty,
      reason: 'Ο δεύτερος χρήστης ξεκινά από καθαρές προεπιλογές.',
    );
    await notifier.setDestinationDirectory(r'D:\tou_deuterou');

    CurrentOperator.activate(_operator(901));
    await notifier.load();
    expect(
      container.read(databaseBackupSettingsProvider).destinationDirectory,
      r'D:\tou_prwtou',
    );
  });

  test(
    'ο διαχειριστής κληρονομεί τη σημερινή κοινή τιμή — ο απλός όχι',
    () async {
      final db = await DatabaseHelper.instance.database;
      await SettingsRepository(db).saveSetting(
        DatabaseBackupSettings.appSettingsKey,
        _bundleWithFolder(r'D:\shmerinos_fakelos'),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(databaseBackupSettingsProvider.notifier);

      CurrentOperator.activate(_operator(910, isAdmin: true));
      await notifier.load();
      expect(
        container.read(databaseBackupSettingsProvider).destinationDirectory,
        r'D:\shmerinos_fakelos',
      );

      CurrentOperator.activate(_operator(911));
      await notifier.load();
      expect(
        container.read(databaseBackupSettingsProvider).destinationDirectory,
        isEmpty,
      );
    },
  );

  test(
    'η «Αλλαγή χρήστη» ξαναφορτώνει το δέμα χωρίς καμία άλλη κλήση',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(databaseBackupSettingsProvider.notifier);

      CurrentOperator.activate(_operator(921));
      await notifier.load();
      await notifier.setDestinationDirectory(r'D:\prosopikos');
      expect(
        container.read(databaseBackupSettingsProvider).destinationDirectory,
        r'D:\prosopikos',
      );

      // Μόνο η αλλαγή ταυτότητας — κανένα ρητό load().
      CurrentOperator.activate(_operator(922));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        container.read(databaseBackupSettingsProvider).destinationDirectory,
        isEmpty,
        reason:
            'Το δέμα του προηγούμενου χρήστη δεν επιτρέπεται να μείνει ενεργό '
            'μετά την αλλαγή.',
      );
    },
  );

  group('Δικαίωμα πλήρους αντιγράφου (Φάση 2)', () {
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

    test('χαλασμένο αρχείο εξηγεί το πρόβλημα, δεν σκάει', () async {
      final dir = Directory.systemTemp.createTempSync('profile_import_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = p.join(dir.path, 'bad.json');
      File(bad).writeAsStringSync('δεν είναι json');

      CurrentOperator.activate(_operator(953));
      final result = await importActiveOperatorSettings(
        pickOpenPath: () async => bad,
      );

      expect(result.isRestored, isFalse);
      expect(result.error, isNotNull);
    });

    test('ακύρωση: τίποτα δεν αλλάζει', () async {
      CurrentOperator.activate(_operator(954));
      final result = await importActiveOperatorSettings(
        pickOpenPath: () async => null,
      );
      expect(result.isRestored, isFalse);
      expect(result.error, isNull);
    });
  });
}
