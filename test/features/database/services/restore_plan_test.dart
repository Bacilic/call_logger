// Καθαρή λογική σχεδίου επαναφοράς — χωρίς αρχεία και χωρίς UI.
//
//   flutter test test/features/database/services/restore_plan_test.dart

import 'package:call_logger/features/database/services/backup_zip_manifest.dart';
import 'package:call_logger/features/database/services/database_zip_pick_restore.dart';
import 'package:call_logger/features/database/services/restore_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const current = r'C:\app\data\call_logger.db';
  const zipPath = r'E:\backups\call_logger_2026-07-25.zip';
  const original = r'D:\old\call_logger.db';

  final knownManifest = BackupZipManifest(
    originalDatabasePath: original,
    databaseFileName: 'call_logger.db',
    createdAt: DateTime.utc(2026, 7, 20),
    appVersion: '0.21.3',
    schemaVersion: 40,
  );

  test('προεπιλογή είναι η τρέχουσα βάση', () {
    expect(
      RestoreDestinationChoice.defaultChoice,
      RestoreDestinationChoice.currentDatabase,
    );
  });

  test('τελική διαδρομή ανά επιλογή προορισμού', () {
    expect(
      resolveRestoreTargetPath(
        choice: RestoreDestinationChoice.currentDatabase,
        currentDatabasePath: current,
        zipPath: zipPath,
        manifest: knownManifest,
      ),
      current,
    );
    expect(
      resolveRestoreTargetPath(
        choice: RestoreDestinationChoice.besideZip,
        currentDatabasePath: current,
        zipPath: zipPath,
        manifest: knownManifest,
      ),
      DatabaseZipPickRestore.targetDatabasePathFor(zipPath),
    );
    expect(
      resolveRestoreTargetPath(
        choice: RestoreDestinationChoice.originalPathFromManifest,
        currentDatabasePath: current,
        zipPath: zipPath,
        manifest: knownManifest,
      ),
      original,
    );
  });

  test('αρχική διαδρομή διαθέσιμη μόνο με manifest, διαφορετική και εγγράψιμη',
      () {
    expect(
      availableRestoreDestinations(
        currentDatabasePath: current,
        zipPath: zipPath,
        manifest: knownManifest,
        originalDirectoryWritable: true,
      ),
      contains(RestoreDestinationChoice.originalPathFromManifest),
    );

    expect(
      availableRestoreDestinations(
        currentDatabasePath: current,
        zipPath: zipPath,
        manifest: BackupZipManifest.unknown(),
        originalDirectoryWritable: true,
      ),
      isNot(contains(RestoreDestinationChoice.originalPathFromManifest)),
    );

    expect(
      availableRestoreDestinations(
        currentDatabasePath: original,
        zipPath: zipPath,
        manifest: knownManifest,
        originalDirectoryWritable: true,
      ),
      isNot(contains(RestoreDestinationChoice.originalPathFromManifest)),
      reason: 'ίδια με την τρέχουσα → δεν έχει νόημα ως ξεχωριστή επιλογή',
    );

    expect(
      availableRestoreDestinations(
        currentDatabasePath: current,
        zipPath: zipPath,
        manifest: knownManifest,
        originalDirectoryWritable: false,
      ),
      isNot(contains(RestoreDestinationChoice.originalPathFromManifest)),
    );
  });

  test('τρέχουσα και δίπλα στο zip είναι πάντα διαθέσιμες', () {
    final choices = availableRestoreDestinations(
      currentDatabasePath: current,
      zipPath: zipPath,
      manifest: BackupZipManifest.unknown(),
      originalDirectoryWritable: false,
    );
    expect(choices, contains(RestoreDestinationChoice.currentDatabase));
    expect(choices, contains(RestoreDestinationChoice.besideZip));
  });

  test('ο διακόπτης ανοίγματος έχει νόημα μόνο εκτός τρέχουσας βάσης', () {
    expect(
      restoreOpenSwitchMeaningful(RestoreDestinationChoice.currentDatabase),
      isFalse,
    );
    expect(
      restoreOpenSwitchMeaningful(RestoreDestinationChoice.besideZip),
      isTrue,
    );
    expect(
      restoreOpenSwitchMeaningful(
        RestoreDestinationChoice.originalPathFromManifest,
      ),
      isTrue,
    );
  });
}
