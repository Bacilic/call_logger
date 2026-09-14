// Αποθηκευτής zoom ανά πίνακα (Διαχείριση Βάσης): τα σφάλματα φόρτωσης
// δεν καταπίνονται σιωπηλά — γράφονται στο ημερολόγιο σφαλμάτων.
//
//   flutter test test/features/database/database_browser_zoom_notifier_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/services/crash_log_service.dart';
import 'package:call_logger/features/database/screens/database_browser_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../test_setup.dart';

const _zoomSettingsKey = 'database_browser_preview_zoom_by_table';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    initSqfliteFfiForTests();
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    tempDir = await Directory.systemTemp.createTemp('db_zoom_notifier_test_');
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<List<File>> errorLogFiles(String dbPath) async {
    final dir = Directory(CrashLogService.logsDirectoryForDatabasePath(dbPath));
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where(
          (f) =>
              p.basename(f.path).startsWith('errors_') &&
              p.basename(f.path).endsWith('.log'),
        )
        .toList();
  }

  test('χαλασμένο JSON zoom: κενή κατάσταση ΚΑΙ εγγραφή στο ημερολόγιο '
      'σφαλμάτων (όχι σιωπηλή κατάποση)', () async {
    final dbPath = '${tempDir.path}/zoom_corrupt.db';
    await DatabaseHelper.bindTestDatabaseFile(dbPath);
    final db = await DatabaseHelper.instance.initializeDatabase();
    await SettingsRepository(db).saveSetting(_zoomSettingsKey, '{χαλασμένο');

    await CrashLogService.initialize(
      databasePath: dbPath,
      appVersion: 'test',
      retentionCount: 5,
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(databaseBrowserZoomByTableProvider, (_, _) {});
    addTearDown(sub.close);

    await container.read(databaseBrowserZoomByTableProvider.notifier).load();

    expect(container.read(databaseBrowserZoomByTableProvider), isEmpty);

    final logs = await errorLogFiles(dbPath);
    final contents = [for (final f in logs) await f.readAsString()].join('\n');
    expect(
      contents.contains('FormatException'),
      isTrue,
      reason:
          'Το σφάλμα ανάγνωσης του zoom πρέπει να γράφεται στο ημερολόγιο '
          'σφαλμάτων, όχι να καταπίνεται. Περιεχόμενο: $contents',
    );
  });

  test('έγκυρο JSON zoom: φορτώνεται κανονικά', () async {
    final dbPath = '${tempDir.path}/zoom_ok.db';
    await DatabaseHelper.bindTestDatabaseFile(dbPath);
    final db = await DatabaseHelper.instance.initializeDatabase();
    await SettingsRepository(db).saveSetting(_zoomSettingsKey, '{"calls":1.5}');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(databaseBrowserZoomByTableProvider, (_, _) {});
    addTearDown(sub.close);

    final notifier = container.read(
      databaseBrowserZoomByTableProvider.notifier,
    );
    await notifier.load();

    expect(notifier.zoomFor('calls'), 1.5);
    expect(notifier.zoomFor('tasks'), 1.0);
  });

  test('φόρτωση πριν από το πρώτο build της οθόνης (κανείς δεν ακούει ακόμη): '
      'η τιμή φτάνει, χωρίς σφάλμα «Ref after disposed»', () async {
    final dbPath = '${tempDir.path}/zoom_no_listener.db';
    await DatabaseHelper.bindTestDatabaseFile(dbPath);
    final db = await DatabaseHelper.instance.initializeDatabase();
    await SettingsRepository(db).saveSetting(_zoomSettingsKey, '{"calls":1.5}');

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Καμία συνδρομή: ακριβώς η στιγμή του initState, όπου η οθόνη ζητά τη
    // φόρτωση πριν προλάβει το πρώτο build να αρχίσει να παρακολουθεί.
    final notifier = container.read(
      databaseBrowserZoomByTableProvider.notifier,
    );
    await notifier.load();

    expect(container.read(databaseBrowserZoomByTableProvider), {'calls': 1.5});
  });

  test('η οθόνη ξηλώνεται ενόσω η φόρτωση τρέχει: καμία εξαίρεση, η τιμή '
      'επιβιώνει για το επόμενο άνοιγμα', () async {
    final dbPath = '${tempDir.path}/zoom_unmount_midway.db';
    await DatabaseHelper.bindTestDatabaseFile(dbPath);
    final db = await DatabaseHelper.instance.initializeDatabase();
    await SettingsRepository(db).saveSetting(_zoomSettingsKey, '{"calls":1.5}');

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final sub = container.listen(databaseBrowserZoomByTableProvider, (_, _) {});
    final notifier = container.read(
      databaseBrowserZoomByTableProvider.notifier,
    );

    // Η αλλαγή βάσης ξαναφορτώνει και μετά ξηλώνει την οθόνη: η φόρτωση
    // βρίσκεται στη μέση όταν φεύγει ο τελευταίος ακροατής.
    final loading = notifier.load();
    sub.close();
    await loading;

    expect(container.read(databaseBrowserZoomByTableProvider), {'calls': 1.5});
  });
}
