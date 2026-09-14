import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/database/database_file_classifier.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/portable_lamp_storage.dart';
import 'backup_zip_health.dart';
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

/// Τι φορητά τμήματα βρέθηκαν μέσα στο `.zip`, και πόσα αρχεία το καθένα.
///
/// Τα πλήθη δεν είναι διακοσμητικά: ο διάλογος επαναφοράς τα δείχνει δίπλα σε
/// κάθε επιλογή, ώστε ο χρήστης να ξέρει τι θα φέρει πριν το ζητήσει.
class BackupZipPortablePresence {
  const BackupZipPortablePresence({
    required this.hasManifest,
    this.mapsCount = 0,
    this.imagesCount = 0,
    this.dictionariesCount = 0,
    this.lampDatabaseCount = 0,
    this.lampDatabaseModified,
  });

  final bool hasManifest;
  final int mapsCount;
  final int imagesCount;
  final int dictionariesCount;
  final int lampDatabaseCount;

  /// Πότε γράφτηκε η βάση Λάμπας που ταξιδεύει μέσα στο αντίγραφο.
  ///
  /// Επιτρέπει στον διάλογο να προειδοποιήσει όταν η τοπική βάση Λάμπας είναι
  /// **νεότερη** από εκείνη του αντιγράφου — το σενάριο όπου η επαναφορά
  /// σβήνει δουλειά αντί να τη σώζει.
  final DateTime? lampDatabaseModified;

  bool get hasMaps => mapsCount > 0;
  bool get hasImages => imagesCount > 0;
  bool get hasDictionaries => dictionariesCount > 0;
  bool get hasLampDatabase => lampDatabaseCount > 0;
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
    this.archiveFailure,
    this.portablePresence = const BackupZipPortablePresence(hasManifest: false),
  });

  final List<BackupZipEligibleCandidate> eligibleCandidates;
  final List<BackupZipRejectedCandidate> rejectedCandidates;
  final bool isFullBackupArchive;
  final int totalDatabaseEntries;
  final bool candidateLimitExceeded;
  final int uncheckedCandidateCount;
  final List<String> cleanupWarnings;

  /// Γιατί το ίδιο το αρχείο δεν διαβάστηκε — `null` όταν διαβάστηκε μια χαρά.
  ///
  /// Χωριστό από το «δεν βρέθηκε βάση μέσα»: ο αποκωδικοποιητής επιστρέφει
  /// άδειο αρχειοθέτη τόσο για κομμένο zip όσο και για έγκυρο zip χωρίς
  /// περιεχόμενο, και τα δύο κατέληγαν στο ίδιο μήνυμα.
  final String? archiveFailure;
  final BackupZipPortablePresence portablePresence;

  /// Σύνοψη τύπου «Βρέθηκαν 7 αρχεία βάσης, 3 είναι βάσεις της εφαρμογής».
  String get summarySentence {
    final failure = archiveFailure;
    if (failure != null) return failure;
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

/// Παρουσία γνωστών φακέλων αντιγράφου και manifest, με πλήθος αρχείων.
///
/// Το [lampDatabaseModified] το δίνει ο καλών που διαβάζει πραγματικό zip —
/// οι σκέτες ονομασίες εγγραφών δεν κουβαλούν ημερομηνία.
BackupZipPortablePresence detectPortablePresence(
  Iterable<String> entryNames, {
  DateTime? lampDatabaseModified,
}) {
  final mapsPrefix = '${BuildingMapStorage.backupZipMapsFolderName}/';
  final imagesPrefix = '${AppConfig.portableImagesDirName}/';
  final dictPrefix = '${AppConfig.portableDictionariesDirName}/';
  final lampPrefix = '${PortableLampStorage.backupZipLampDbFolderName}/';

  var hasManifest = false;
  var mapsCount = 0;
  var imagesCount = 0;
  var dictionariesCount = 0;
  var lampDatabaseCount = 0;

  for (final raw in entryNames) {
    final name = raw.replaceAll('\\', '/');
    if (name == BackupZipManifest.zipEntryName) {
      hasManifest = true;
      continue;
    }
    // Η σκέτη εγγραφή φακέλου δηλώνει παρουσία, όχι περιεχόμενο — γι' αυτό
    // μετρούν μόνο τα ονόματα που συνεχίζουν πέρα από το πρόθεμα.
    if (name.startsWith(mapsPrefix)) {
      if (name.length > mapsPrefix.length) mapsCount++;
    } else if (name.startsWith(imagesPrefix)) {
      if (name.length > imagesPrefix.length) imagesCount++;
    } else if (name.startsWith(dictPrefix)) {
      if (name.length > dictPrefix.length) dictionariesCount++;
    } else if (name.startsWith(lampPrefix)) {
      if (name.length > lampPrefix.length) lampDatabaseCount++;
    }
  }

  return BackupZipPortablePresence(
    hasManifest: hasManifest,
    mapsCount: mapsCount,
    imagesCount: imagesCount,
    dictionariesCount: dictionariesCount,
    lampDatabaseCount: lampDatabaseCount,
    lampDatabaseModified: lampDatabaseModified,
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

  final bytes = await zipFile.readAsBytes();

  // Πρώτα το ίδιο το αρχείο, και μετά το περιεχόμενό του. Ο αποκωδικοποιητής
  // δεν ξεχωρίζει το κομμένο zip από το άδειο — και τα δύο του βγαίνουν ως
  // «κανένα αρχείο μέσα».
  final health = inspectBackupArchiveBytes(bytes);
  final healthMessage = backupArchiveHealthMessage(health);
  if (healthMessage != null) {
    return BackupZipInventory(
      eligibleCandidates: const [],
      rejectedCandidates: const [],
      isFullBackupArchive: false,
      totalDatabaseEntries: 0,
      archiveFailure: healthMessage,
    );
  }

  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    return BackupZipInventory(
      eligibleCandidates: const [],
      rejectedCandidates: const [],
      isFullBackupArchive: false,
      totalDatabaseEntries: 0,
      archiveFailure:
          'Το αντίγραφο δεν μπόρεσε να ανοίξει. Δοκιμάστε παλαιότερο '
          'αντίγραφο.',
      cleanupWarnings: ['Αποτυχία ανάγνωσης/αποσυμπίεσης zip: $e'],
    );
  }

  final listed = <BackupZipListedEntry>[];
  final otherNames = <String>[];
  final lampPrefix = '${PortableLampStorage.backupZipLampDbFolderName}/';
  DateTime? lampModified;
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.replaceAll('\\', '/');
    otherNames.add(name);
    if (name.startsWith(lampPrefix) && f.lastModTime > 0) {
      lampModified = DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000);
    }
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
    lampDatabaseModified: lampModified,
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
  DateTime? lampDatabaseModified,
}) async {
  final allNames = <String>{
    ...otherEntryNames.map((n) => n.replaceAll('\\', '/')),
    ...entries.map((e) => e.entryName.replaceAll('\\', '/')),
  };
  final portablePresence = detectPortablePresence(
    allNames,
    lampDatabaseModified: lampDatabaseModified,
  );
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
      eligible.add(
        BackupZipEligibleCandidate(
          entryName: entryName,
          displayName: displayName,
          sizeBytes: sizeBytes,
          profile: profile,
        ),
      );
      return;
    case DatabaseFileKind.incompleteCallLogger:
      // Μένει στη λίστα ώστε ο χρήστης να δει ΓΙΑΤΙ δεν του κάνει — αλλά
      // σημαίνεται, γιατί μια βάση με λειψούς πίνακες δεν ανοίγει ποτέ. Ο
      // διάλογος επαναφοράς κλειδώνει το κουτάκι της.
      final missing = profile.missingCoreTables.join(', ');
      eligible.add(
        BackupZipEligibleCandidate(
          entryName: entryName,
          displayName: displayName,
          sizeBytes: sizeBytes,
          profile: profile,
          checkFailed: true,
          checkWarning: missing.isEmpty
              ? 'Ελλιπής βάση της Καταγραφής Κλήσεων — λείπουν βασικοί '
                    'πίνακες και δεν μπορεί να ανοίξει.'
              : 'Ελλιπής βάση — λείπουν οι πίνακες: $missing. Δεν μπορεί να '
                    'ανοίξει.',
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
