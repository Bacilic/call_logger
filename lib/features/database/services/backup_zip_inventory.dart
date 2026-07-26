import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/database/database_file_classifier.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/portable_lamp_storage.dart';
import 'backup_zip_manifest.dart';

/// Προφίλ αρχείου βάσης (προεπιλογή: [profileDatabaseFile]).
typedef DatabaseFileProfiler =
    Future<DatabaseFileProfile> Function(String path);

/// Προεπιλεγμένο ανώτατο πλήθος υποψηφίων που προφιλάρονται ανά απογραφή.
const int kBackupZipMaxCandidatesToCheck = 20;

/// Εγγραφή `.db` για injectable απογραφή (χωρίς πραγματικό zip).
class BackupZipListedEntry {
  const BackupZipListedEntry({
    required this.entryName,
    required this.sizeBytes,
    required this.bytes,
  });

  final String entryName;
  final int sizeBytes;
  final List<int> bytes;
}

/// Έγκυρος ή επιλέξιμος-με-προειδοποίηση υποψήφιος επαναφοράς.
class BackupZipEligibleCandidate {
  const BackupZipEligibleCandidate({
    required this.entryName,
    required this.displayName,
    required this.sizeBytes,
    required this.profile,
    this.checkFailed = false,
    this.checkWarning,
  });

  final String entryName;
  final String displayName;
  final int sizeBytes;
  final DatabaseFileProfile profile;
  final bool checkFailed;
  final String? checkWarning;
}

/// Απορριφθείσα εγγραφή βάσης με ονομαστική αιτία σε γλώσσα χρήστη.
class BackupZipRejectedCandidate {
  const BackupZipRejectedCandidate({
    required this.entryName,
    required this.displayName,
    required this.sizeBytes,
    required this.reason,
  });

  final String entryName;
  final String displayName;
  final int sizeBytes;
  final String reason;
}

/// Τι φορητά τμήματα βρέθηκαν μέσα στο `.zip` (για προειδοποίηση πλήρους αντιγράφου).
class BackupZipPortablePresence {
  const BackupZipPortablePresence({
    required this.hasManifest,
    required this.hasMaps,
    required this.hasImages,
    required this.hasDictionaries,
    required this.hasLampDatabase,
  });

  final bool hasManifest;
  final bool hasMaps;
  final bool hasImages;
  final bool hasDictionaries;
  final bool hasLampDatabase;

  /// Περιγραφή για τον χρήστη των στοιχείων που θα επαναφερθούν μαζί με τη βάση.
  String describeFoundPortables() {
    final parts = <String>[];
    if (hasMaps) parts.add('κατόψεις');
    if (hasImages) parts.add('εικονίδια');
    if (hasDictionaries) parts.add('λεξικό');
    if (hasLampDatabase) parts.add('βάση Λάμπας');
    if (parts.isEmpty) return 'φορητά αρχεία της εφαρμογής';
    if (parts.length == 1) return parts.single;
    final last = parts.removeLast();
    return '${parts.join(', ')} και $last';
  }
}

/// Απογραφή περιεχομένου αντιγράφου `.zip` ως προς αρχεία βάσης.
class BackupZipInventory {
  const BackupZipInventory({
    required this.eligibleCandidates,
    required this.rejectedCandidates,
    required this.isFullBackupArchive,
    required this.totalDatabaseEntries,
    this.candidateLimitExceeded = false,
    this.uncheckedCandidateCount = 0,
    this.cleanupWarnings = const <String>[],
    this.portablePresence = const BackupZipPortablePresence(
      hasManifest: false,
      hasMaps: false,
      hasImages: false,
      hasDictionaries: false,
      hasLampDatabase: false,
    ),
  });

  final List<BackupZipEligibleCandidate> eligibleCandidates;
  final List<BackupZipRejectedCandidate> rejectedCandidates;
  final bool isFullBackupArchive;
  final int totalDatabaseEntries;
  final bool candidateLimitExceeded;
  final int uncheckedCandidateCount;
  final List<String> cleanupWarnings;
  final BackupZipPortablePresence portablePresence;

  /// Σύνοψη τύπου «Βρέθηκαν 7 αρχεία βάσης, 3 είναι βάσεις της εφαρμογής».
  String get summarySentence {
    final eligible = eligibleCandidates.length;
    final total = totalDatabaseEntries;
    if (total == 0) {
      return 'Δεν βρέθηκε κανένα αρχείο βάσης (.db) μέσα στο αντίγραφο.';
    }
    if (eligible == 0) {
      return 'Βρέθηκαν $total αρχεία βάσης, κανένα δεν είναι βάση της εφαρμογής.';
    }
    if (eligible == total) {
      return 'Βρέθηκαν $total αρχεία βάσης'
          '${eligible == 1 ? '' : ', όλα βάσεις της εφαρμογής'}.';
    }
    return 'Βρέθηκαν $total αρχεία βάσης, $eligible '
        '${eligible == 1 ? 'είναι βάση' : 'είναι βάσεις'} της εφαρμογής.';
  }
}

/// Αναγνώριση πλήρους αντιγράφου από φακέλους σταθερών + manifest (όχι όνομα αρχείου).
bool detectFullBackupArchiveStructure(Iterable<String> entryNames) {
  final presence = detectPortablePresence(entryNames);
  return presence.hasManifest &&
      (presence.hasMaps ||
          presence.hasImages ||
          presence.hasDictionaries ||
          presence.hasLampDatabase);
}

/// Παρουσία γνωστών φακέλων αντιγράφου και manifest.
BackupZipPortablePresence detectPortablePresence(Iterable<String> entryNames) {
  final mapsPrefix = '${BuildingMapStorage.backupZipMapsFolderName}/';
  final imagesPrefix = '${AppConfig.portableImagesDirName}/';
  final dictPrefix = '${AppConfig.portableDictionariesDirName}/';
  final lampPrefix = '${PortableLampStorage.backupZipLampDbFolderName}/';

  var hasManifest = false;
  var hasMaps = false;
  var hasImages = false;
  var hasDictionaries = false;
  var hasLampDatabase = false;

  for (final raw in entryNames) {
    final name = raw.replaceAll('\\', '/');
    if (name == BackupZipManifest.zipEntryName) {
      hasManifest = true;
      continue;
    }
    if (name.startsWith(mapsPrefix) ||
        name == mapsPrefix.substring(0, mapsPrefix.length - 1)) {
      hasMaps = true;
    } else if (name.startsWith(imagesPrefix) ||
        name == AppConfig.portableImagesDirName) {
      hasImages = true;
    } else if (name.startsWith(dictPrefix) ||
        name == AppConfig.portableDictionariesDirName) {
      hasDictionaries = true;
    } else if (name.startsWith(lampPrefix) ||
        name == PortableLampStorage.backupZipLampDbFolderName) {
      hasLampDatabase = true;
    }
  }

  return BackupZipPortablePresence(
    hasManifest: hasManifest,
    hasMaps: hasMaps,
    hasImages: hasImages,
    hasDictionaries: hasDictionaries,
    hasLampDatabase: hasLampDatabase,
  );
}

/// Απογραφή πραγματικού `.zip` με injectable profiler και ακροατή προόδου.
Future<BackupZipInventory> inventoryBackupZip(
  String zipPath, {
  DatabaseFileProfiler? profile,
  void Function(int current, int total)? onProgress,
  int maxCandidatesToCheck = kBackupZipMaxCandidatesToCheck,
  String? workDirectory,
}) async {
  final zipFile = File(zipPath);
  if (!await zipFile.exists()) {
    return const BackupZipInventory(
      eligibleCandidates: [],
      rejectedCandidates: [],
      isFullBackupArchive: false,
      totalDatabaseEntries: 0,
      cleanupWarnings: ['Το αρχείο zip δεν βρέθηκε.'],
    );
  }

  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
  } catch (e) {
    return BackupZipInventory(
      eligibleCandidates: const [],
      rejectedCandidates: const [],
      isFullBackupArchive: false,
      totalDatabaseEntries: 0,
      cleanupWarnings: ['Αποτυχία ανάγνωσης/αποσυμπίεσης zip: $e'],
    );
  }

  final listed = <BackupZipListedEntry>[];
  final otherNames = <String>[];
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.replaceAll('\\', '/');
    otherNames.add(name);
    if (!name.toLowerCase().endsWith('.db')) continue;
    listed.add(
      BackupZipListedEntry(
        entryName: name,
        sizeBytes: f.size,
        bytes: List<int>.from(f.content as List<int>),
      ),
    );
  }

  return inventoryBackupZipListedEntries(
    entries: listed,
    otherEntryNames: otherNames,
    profile: profile ?? profileDatabaseFile,
    onProgress: onProgress,
    maxCandidatesToCheck: maxCandidatesToCheck,
    workDirectory: workDirectory,
  );
}

/// Απογραφή από έτοιμη λίστα εγγραφών (τεστ / injectable εξαγωγέας).
Future<BackupZipInventory> inventoryBackupZipListedEntries({
  required List<BackupZipListedEntry> entries,
  required Iterable<String> otherEntryNames,
  required DatabaseFileProfiler profile,
  void Function(int current, int total)? onProgress,
  int maxCandidatesToCheck = kBackupZipMaxCandidatesToCheck,
  String? workDirectory,
}) async {
  final allNames = <String>{
    ...otherEntryNames.map((n) => n.replaceAll('\\', '/')),
    ...entries.map((e) => e.entryName.replaceAll('\\', '/')),
  };
  final portablePresence = detectPortablePresence(allNames);
  final isFull = detectFullBackupArchiveStructure(allNames);

  final lampPrefix = '${PortableLampStorage.backupZipLampDbFolderName}/';
  final eligible = <BackupZipEligibleCandidate>[];
  final rejected = <BackupZipRejectedCandidate>[];
  final cleanupWarnings = <String>[];

  final toCheck = <BackupZipListedEntry>[];
  for (final entry in entries) {
    final name = entry.entryName.replaceAll('\\', '/');
    final display = p.basename(name);
    if (name.startsWith(lampPrefix)) {
      rejected.add(
        BackupZipRejectedCandidate(
          entryName: name,
          displayName: display,
          sizeBytes: entry.sizeBytes,
          reason: 'βάση Λάμπας',
        ),
      );
      continue;
    }
    toCheck.add(
      BackupZipListedEntry(
        entryName: name,
        sizeBytes: entry.sizeBytes,
        bytes: entry.bytes,
      ),
    );
  }

  final limit = maxCandidatesToCheck < 0 ? 0 : maxCandidatesToCheck;
  final limited = toCheck.take(limit).toList(growable: false);
  final unchecked = toCheck.length - limited.length;
  final totalForProgress = limited.length;

  Directory? workDir;
  try {
    if (workDirectory != null && workDirectory.trim().isNotEmpty) {
      workDir = Directory(workDirectory.trim());
      await workDir.create(recursive: true);
    } else {
      workDir = await Directory.systemTemp.createTemp('backup_zip_inv_');
    }
  } catch (e) {
    cleanupWarnings.add('Δεν δημιουργήθηκε προσωρινός φάκελος απογραφής: $e');
    return BackupZipInventory(
      eligibleCandidates: eligible,
      rejectedCandidates: rejected,
      isFullBackupArchive: isFull,
      totalDatabaseEntries: entries.length,
      candidateLimitExceeded: unchecked > 0,
      uncheckedCandidateCount: unchecked,
      cleanupWarnings: cleanupWarnings,
      portablePresence: portablePresence,
    );
  }

  var index = 0;
  for (final entry in limited) {
    index++;
    onProgress?.call(index, totalForProgress);

    final display = p.basename(entry.entryName);
    final safe = entry.entryName.replaceAll('/', '__').replaceAll('\\', '__');
    final tempPath = p.join(workDir.path, 'inv_${safe}_$index.db');
    final tempFile = File(tempPath);

    try {
      await tempFile.writeAsBytes(Uint8List.fromList(entry.bytes), flush: true);
    } catch (e) {
      eligible.add(
        BackupZipEligibleCandidate(
          entryName: entry.entryName,
          displayName: display,
          sizeBytes: entry.sizeBytes,
          profile: const DatabaseFileProfile(
            kind: DatabaseFileKind.undetermined,
          ),
          checkFailed: true,
          checkWarning:
              'Ο έλεγχος απέτυχε (δεν γράφτηκε προσωρινό αρχείο). '
              'Μπορείτε να το επιλέξετε αν είναι το μόνο διαθέσιμο αντίγραφο.',
        ),
      );
      continue;
    }

    DatabaseFileProfile fileProfile;
    try {
      fileProfile = await profile(tempPath);
    } catch (_) {
      fileProfile = const DatabaseFileProfile(
        kind: DatabaseFileKind.undetermined,
      );
    }

    final cleanupMsg = await _deleteTempQuietly(tempPath);
    if (cleanupMsg != null) {
      cleanupWarnings.add(cleanupMsg);
    }

    _classifyProfiledCandidate(
      entryName: entry.entryName,
      displayName: display,
      sizeBytes: entry.sizeBytes,
      profile: fileProfile,
      eligible: eligible,
      rejected: rejected,
    );
  }

  try {
    if (workDirectory == null || workDirectory.trim().isEmpty) {
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    }
  } catch (e) {
    cleanupWarnings.add('Δεν καθαρίστηκε ο προσωρινός φάκελος απογραφής: $e');
  }

  return BackupZipInventory(
    eligibleCandidates: eligible,
    rejectedCandidates: rejected,
    isFullBackupArchive: isFull,
    totalDatabaseEntries: entries.length,
    candidateLimitExceeded: unchecked > 0,
    uncheckedCandidateCount: unchecked,
    cleanupWarnings: cleanupWarnings,
    portablePresence: portablePresence,
  );
}

void _classifyProfiledCandidate({
  required String entryName,
  required String displayName,
  required int sizeBytes,
  required DatabaseFileProfile profile,
  required List<BackupZipEligibleCandidate> eligible,
  required List<BackupZipRejectedCandidate> rejected,
}) {
  switch (profile.kind) {
    case DatabaseFileKind.callLogger:
    case DatabaseFileKind.incompleteCallLogger:
      eligible.add(
        BackupZipEligibleCandidate(
          entryName: entryName,
          displayName: displayName,
          sizeBytes: sizeBytes,
          profile: profile,
        ),
      );
      return;
    case DatabaseFileKind.undetermined:
      eligible.add(
        BackupZipEligibleCandidate(
          entryName: entryName,
          displayName: displayName,
          sizeBytes: sizeBytes,
          profile: profile,
          checkFailed: true,
          checkWarning:
              'Ο έλεγχος απέτυχε — το αρχείο μπορεί να είναι κατεστραμμένο. '
              'Επιλέξτε το μόνο αν είναι το μοναδικό διαθέσιμο αντίγραφο.',
        ),
      );
      return;
    case DatabaseFileKind.lamp:
      rejected.add(
        BackupZipRejectedCandidate(
          entryName: entryName,
          displayName: displayName,
          sizeBytes: sizeBytes,
          reason: 'βάση Λάμπας',
        ),
      );
      return;
    case DatabaseFileKind.hybrid:
      rejected.add(
        BackupZipRejectedCandidate(
          entryName: entryName,
          displayName: displayName,
          sizeBytes: sizeBytes,
          reason: 'ανακατεμένο σχήμα Καταγραφής και Λάμπας',
        ),
      );
      return;
    case DatabaseFileKind.empty:
      rejected.add(
        BackupZipRejectedCandidate(
          entryName: entryName,
          displayName: displayName,
          sizeBytes: sizeBytes,
          reason: 'κενό αρχείο',
        ),
      );
      return;
    case DatabaseFileKind.unknown:
      rejected.add(
        BackupZipRejectedCandidate(
          entryName: entryName,
          displayName: displayName,
          sizeBytes: sizeBytes,
          reason: 'άγνωστο σχήμα',
        ),
      );
      return;
  }
}

Future<String?> _deleteTempQuietly(String path) async {
  final failures = <String>[];
  for (final candidate in <String>[path, '$path-wal', '$path-shm']) {
    try {
      final f = File(candidate);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (e) {
      failures.add('${p.basename(candidate)}: $e');
    }
  }
  if (failures.isEmpty) return null;
  return 'Δεν καθαρίστηκε προσωρινό αρχείο απογραφής:\n${failures.join('\n')}';
}
