import 'dart:io';

import 'package:call_logger/core/database/backup_destination_hint.dart';
import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/providers/database_backup_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late Directory validBackupDir;
  late Directory missingBackupDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_hint_');
    validBackupDir = Directory(p.join(tempDir.path, 'backups'));
    await validBackupDir.create(recursive: true);
    missingBackupDir = Directory(p.join(tempDir.path, 'gone_backups'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('επιστρέφει φάκελο από Riverpod όταν είναι έγκυρος', () async {
    final container = ProviderContainer(
      overrides: [
        databaseBackupSettingsProvider.overrideWith(
          () => _FixedBackupSettingsNotifier(
            DatabaseBackupSettings.defaults().copyWith(
              destinationDirectory: validBackupDir.path,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final hint = await resolveValidBackupDestinationHint(
      container: container,
    );
    expect(hint, validBackupDir.path);
  });

  test('αγνοεί μη υπάρχοντα φάκελο από Riverpod', () async {
    final container = ProviderContainer(
      overrides: [
        databaseBackupSettingsProvider.overrideWith(
          () => _FixedBackupSettingsNotifier(
            DatabaseBackupSettings.defaults().copyWith(
              destinationDirectory: missingBackupDir.path,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final hint = await resolveValidBackupDestinationHint(
      container: container,
      candidateDatabasePaths: const <String>[],
      includeDefaultDbPath: false,
    );
    expect(hint, isNull);
  });
}

class _FixedBackupSettingsNotifier extends DatabaseBackupSettingsNotifier {
  _FixedBackupSettingsNotifier(this._fixed);

  final DatabaseBackupSettings _fixed;

  @override
  DatabaseBackupSettings build() => _fixed;
}
