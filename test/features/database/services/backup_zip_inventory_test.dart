// Απογραφή περιεχομένου .zip αντιγράφου — χωρίς πραγματική SQLite.
//
//   flutter test test/features/database/services/backup_zip_inventory_test.dart

import 'dart:typed_data';

import 'package:call_logger/core/config/app_config.dart';
import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/services/building_map_storage.dart';
import 'package:call_logger/core/services/portable_lamp_storage.dart';
import 'package:call_logger/features/database/services/backup_zip_inventory.dart';
import 'package:call_logger/features/database/services/backup_zip_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<DatabaseFileProfile> Function(String) profilerFor(
    Map<String, DatabaseFileKind> byEntry,
  ) {
    return (path) async {
      for (final entry in byEntry.entries) {
        if (path.contains(entry.key.replaceAll('/', '_')) ||
            path.endsWith(entry.key.split('/').last)) {
          return DatabaseFileProfile(kind: entry.value);
        }
      }
      // Το προσωρινό αρχείο περιέχει το sanitized entry name.
      for (final entry in byEntry.entries) {
        final safe = entry.key.replaceAll('/', '__').replaceAll('\\', '__');
        if (path.contains(safe)) {
          return DatabaseFileProfile(kind: entry.value);
        }
      }
      return const DatabaseFileProfile(kind: DatabaseFileKind.undetermined);
    };
  }

  test(
    'επτά αρχεία βάσης: τρεις έγκυροι, τέσσερις απορριφθέντες με ονομαστική αιτία· '
    'η βάση Λάμπας στον φάκελό της δεν είναι υποψήφια',
    () async {
      final entries = <BackupZipListedEntry>[
        BackupZipListedEntry(
          entryName: 'giannis.db',
          sizeBytes: 100,
          bytes: Uint8List.fromList([1]),
        ),
        BackupZipListedEntry(
          entryName: 'db1.db',
          sizeBytes: 110,
          bytes: Uint8List.fromList([2]),
        ),
        BackupZipListedEntry(
          entryName: 'call_logger.db',
          sizeBytes: 120,
          bytes: Uint8List.fromList([3]),
        ),
        BackupZipListedEntry(
          entryName: 'noise_unknown.db',
          sizeBytes: 50,
          bytes: Uint8List.fromList([4]),
        ),
        BackupZipListedEntry(
          entryName: 'emptyish.db',
          sizeBytes: 40,
          bytes: Uint8List.fromList([5]),
        ),
        BackupZipListedEntry(
          entryName: 'hybrid.db',
          sizeBytes: 60,
          bytes: Uint8List.fromList([6]),
        ),
        BackupZipListedEntry(
          entryName: '${PortableLampStorage.backupZipLampDbFolderName}/lamp.db',
          sizeBytes: 200,
          bytes: Uint8List.fromList([7]),
        ),
      ];

      final kinds = <String, DatabaseFileKind>{
        'giannis.db': DatabaseFileKind.callLogger,
        'db1.db': DatabaseFileKind.callLogger,
        'call_logger.db': DatabaseFileKind.incompleteCallLogger,
        'noise_unknown.db': DatabaseFileKind.unknown,
        'emptyish.db': DatabaseFileKind.empty,
        'hybrid.db': DatabaseFileKind.hybrid,
        '${PortableLampStorage.backupZipLampDbFolderName}/lamp.db':
            DatabaseFileKind.lamp,
      };

      final inventory = await inventoryBackupZipListedEntries(
        entries: entries,
        otherEntryNames: const <String>[],
        profile: profilerFor(kinds),
      );

      expect(inventory.eligibleCandidates, hasLength(3));
      expect(inventory.eligibleCandidates.map((c) => c.entryName).toSet(), {
        'giannis.db',
        'db1.db',
        'call_logger.db',
      });
      expect(inventory.rejectedCandidates, hasLength(4));
      expect(
        inventory.rejectedCandidates.any(
          (r) => r.entryName.startsWith(
            '${PortableLampStorage.backupZipLampDbFolderName}/',
          ),
        ),
        isTrue,
      );
      expect(
        inventory.rejectedCandidates.map((r) => r.reason),
        everyElement(isNotEmpty),
      );
      expect(
        inventory.eligibleCandidates.any((c) => c.entryName.contains('lamp')),
        isFalse,
      );
    },
  );

  test(
    'πλήρες αντίγραφο ασφαλείας αναγνωρίζεται από φακέλους + manifest, όχι από όνομα zip',
    () async {
      final full = await inventoryBackupZipListedEntries(
        entries: [
          BackupZipListedEntry(
            entryName: 'call_logger.db',
            sizeBytes: 10,
            bytes: Uint8List.fromList([1]),
          ),
        ],
        otherEntryNames: [
          BackupZipManifest.zipEntryName,
          '${BuildingMapStorage.backupZipMapsFolderName}/floor1.png',
          '${AppConfig.portableImagesDirName}/icon.png',
        ],
        profile: (_) async =>
            const DatabaseFileProfile(kind: DatabaseFileKind.callLogger),
      );
      expect(full.isFullBackupArchive, isTrue);

      final bare = await inventoryBackupZipListedEntries(
        entries: [
          BackupZipListedEntry(
            entryName: 'call_logger.db',
            sizeBytes: 10,
            bytes: Uint8List.fromList([1]),
          ),
        ],
        otherEntryNames: const <String>[],
        profile: (_) async =>
            const DatabaseFileProfile(kind: DatabaseFileKind.callLogger),
      );
      expect(bare.isFullBackupArchive, isFalse);
    },
  );

  test('ανώτατο όριο υποψηφίων δηλώνεται ρητά', () async {
    final entries = List<BackupZipListedEntry>.generate(
      5,
      (i) => BackupZipListedEntry(
        entryName: 'db_$i.db',
        sizeBytes: 10 + i,
        bytes: Uint8List.fromList([i]),
      ),
    );

    final inventory = await inventoryBackupZipListedEntries(
      entries: entries,
      otherEntryNames: const <String>[],
      maxCandidatesToCheck: 3,
      profile: (_) async =>
          const DatabaseFileProfile(kind: DatabaseFileKind.callLogger),
    );

    expect(inventory.eligibleCandidates, hasLength(3));
    expect(inventory.candidateLimitExceeded, isTrue);
    expect(inventory.uncheckedCandidateCount, 2);
  });

  test('αποτυχία ελέγχου παραμένει επιλέξιμη με προειδοποίηση', () async {
    final inventory = await inventoryBackupZipListedEntries(
      entries: [
        BackupZipListedEntry(
          entryName: 'broken.db',
          sizeBytes: 10,
          bytes: Uint8List.fromList([1]),
        ),
      ],
      otherEntryNames: const <String>[],
      profile: (_) async =>
          const DatabaseFileProfile(kind: DatabaseFileKind.undetermined),
    );

    expect(inventory.eligibleCandidates, hasLength(1));
    expect(inventory.eligibleCandidates.single.checkFailed, isTrue);
    expect(inventory.eligibleCandidates.single.checkWarning, isNotEmpty);
  });
}
