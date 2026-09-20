/// Ανοίγει το αντίγραφο που μόλις γράφτηκε και ρωτά αν στέκει.
///
/// **Γιατί υπάρχει:** ως τώρα η δημιουργία αντιγράφου τελείωνε με «Το
/// αντίγραφο ολοκληρώθηκε» αμέσως μόλις γραφόταν το αρχείο. Ένας δίσκος που
/// γέμισε στη μέση, ένα δίκτυο που κόπηκε ή μια βάση που αντιγράφηκε ενώ
/// κάποιος έγραφε, δίνουν αρχείο **που υπάρχει** — και η ζημιά ανακαλύπτεται
/// τη μόνη στιγμή που δεν αντέχει ανακάλυψη: την ώρα της επαναφοράς.
///
/// Ο έλεγχος διαβάζει **από τον δίσκο**, ποτέ από τη μνήμη του κώδικα που
/// μόλις έγραψε: το ζητούμενο είναι αν άντεξε το γράψιμο, όχι αν ήταν σωστά
/// τα bytes πριν φύγουν.
///
/// Το κόστος είναι μετρημένο και μικρό — `quick_check` σε τοπική βάση 10 MB
/// κοστίζει ~31 ms — γι' αυτό τρέχει σε **κάθε** αντίγραφο, και του
/// κλεισίματος.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_integrity_probe.dart';
import '../../../core/services/building_map_storage.dart';
import 'backup_zip_health.dart';

/// Τι απάντησε η επαλήθευση.
enum BackupVerificationStatus {
  /// Το αρχείο ανοίγει και η βάση μέσα του στέκει.
  ok,

  /// Το ίδιο το αρχείο δεν διαβάζεται: κενό, κομμένο, ή δεν είναι αντίγραφο.
  brokenArchive,

  /// Το αρχείο διαβάζεται, αλλά η βάση μέσα του είναι χαλασμένη.
  corruptDatabase,

  /// Δεν βγήκε απάντηση — κλείδωμα, δικαιώματα, δίκτυο που δεν απαντά.
  ///
  /// **Ποτέ δεν εκλαμβάνεται ως ζημιά:** ένα αντίγραφο σε φάκελο δικτύου που
  /// έφυγε για δέκα δευτερόλεπτα δεν είναι χαλασμένο, και η μετονομασία του σε
  /// «ΧΑΛΑΣΜΕΝΟ» θα ήταν χειρότερη από τη σιωπή.
  inconclusive,
}

/// Η ετυμηγορία μαζί με τα λόγια της.
class BackupVerificationResult {
  const BackupVerificationResult({
    required this.status,
    this.message,
    this.rawDetail,
  });

  static const BackupVerificationResult ok = BackupVerificationResult(
    status: BackupVerificationStatus.ok,
  );

  final BackupVerificationStatus status;

  /// Τι διαβάζει ο χειριστής· `null` όταν δεν υπάρχει τίποτα να πει.
  final String? message;

  /// Το ωμό κείμενο του σφάλματος, για όποιον κληθεί να βοηθήσει.
  final String? rawDetail;

  /// Απόδειξη ζημιάς — μόνο τότε σημαδεύεται το αρχείο.
  bool get isBroken =>
      status == BackupVerificationStatus.brokenArchive ||
      status == BackupVerificationStatus.corruptDatabase;
}

/// Το πρόσθετο που μπαίνει στο όνομα ενός αντιγράφου που δεν πέρασε.
///
/// Ελληνικά και κεφαλαία επίτηδες: το όνομα διαβάζεται από άνθρωπο μέσα σε
/// φάκελο με δεκάδες αρχεία, όχι από κώδικα.
const String kBrokenBackupNameMarker = 'ΧΑΛΑΣΜΕΝΟ';

/// Επαληθεύει το αντίγραφο που μόλις γράφτηκε στο [artifactPath].
///
/// Δέχεται και τις δύο μορφές που παράγει η εφαρμογή: σκέτο `.db` (γρήγορο
/// αντίγραφο) και `.zip` (πλήρες, με τα φορητά αρχεία μαζί).
Future<BackupVerificationResult> verifyBackupArtifact(
  String artifactPath,
) async {
  final file = File(artifactPath);
  if (!await file.exists()) {
    return const BackupVerificationResult(
      status: BackupVerificationStatus.brokenArchive,
      message:
          'Το αρχείο του αντιγράφου δεν βρέθηκε αμέσως μετά τη δημιουργία του.',
    );
  }

  if (p.extension(artifactPath).toLowerCase() == '.zip') {
    return _verifyZipBackup(file);
  }
  return _verifyDatabaseFile(artifactPath);
}

/// Σημαδεύει ένα αντίγραφο που δεν πέρασε, χωρίς να το σβήσει.
///
/// **Η μετονομασία είναι η ασφαλής προεπιλογή σε κάθε ροή**, και ιδίως στο
/// κλείσιμο της εφαρμογής, όπου δεν υπάρχει κανείς να ρωτηθεί: το αρχείο μένει
/// για όποιον θέλει να το εξετάσει, αλλά το όνομά του δεν επιτρέπει πια να
/// περάσει για υγιές μέσα σε μια λίστα αντιγράφων.
///
/// Επιστρέφει τη νέα διαδρομή, ή `null` αν η μετονομασία δεν έγινε — οπότε ο
/// καλών κρατά την παλιά και το λέει στο ημερολόγιο.
Future<String?> markBackupArtifactAsBroken(String artifactPath) async {
  final file = File(artifactPath);
  final dir = p.dirname(artifactPath);
  final ext = p.extension(artifactPath);
  final stem = p.basenameWithoutExtension(artifactPath);

  // Αν η προηγούμενη προσπάθεια άφησε ήδη σημαδεμένο αρχείο με το ίδιο όνομα,
  // ο μετρητής κρατά και τα δύο: ένα χαλασμένο αντίγραφο δεν σβήνει άλλο.
  var candidate = p.join(dir, '${stem}_$kBrokenBackupNameMarker$ext');
  var counter = 2;
  while (await File(candidate).exists()) {
    candidate = p.join(dir, '${stem}_${kBrokenBackupNameMarker}_$counter$ext');
    counter++;
  }

  try {
    await file.rename(candidate);
    return candidate;
  } catch (_) {
    return null;
  }
}

/// Ένα `.zip`: πρώτα το περιτύλιγμα, μετά η βάση μέσα του.
Future<BackupVerificationResult> _verifyZipBackup(File file) async {
  final List<int> bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (e) {
    return BackupVerificationResult(
      status: BackupVerificationStatus.inconclusive,
      message: 'Το αντίγραφο δεν ήταν δυνατό να ξαναδιαβαστεί για έλεγχο.',
      rawDetail: e.toString(),
    );
  }

  // Η ίδια κρίση με την επαναφορά, από το ίδιο σημείο: ένα κομμένο zip πρέπει
  // να λέει «κομμένο» και εδώ και εκεί, αλλιώς οι δύο οθόνες μαλώνουν.
  final healthMessage = backupArchiveHealthMessage(
    inspectBackupArchiveBytes(bytes),
  );
  if (healthMessage != null) {
    return BackupVerificationResult(
      status: BackupVerificationStatus.brokenArchive,
      message: healthMessage,
    );
  }

  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    return BackupVerificationResult(
      status: BackupVerificationStatus.brokenArchive,
      message: 'Το αντίγραφο δεν αποσυμπιέζεται.',
      rawDetail: e.toString(),
    );
  }

  ArchiveFile? dbEntry;
  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    if (entry.name.replaceAll('\\', '/') ==
        BuildingMapStorage.backupZipDbFileName) {
      dbEntry = entry;
      break;
    }
  }

  if (dbEntry == null) {
    return const BackupVerificationResult(
      status: BackupVerificationStatus.brokenArchive,
      message: 'Το αντίγραφο δεν περιέχει τη βάση δεδομένων.',
    );
  }

  // Προσωρινός φάκελος του συστήματος, ποτέ δίπλα στο αντίγραφο: ο φάκελος
  // αντιγράφων είναι συχνά σε δίκτυο, και ένα μισοσβησμένο βοηθητικό αρχείο
  // εκεί μπερδεύει την επόμενη απογραφή.
  Directory? staging;
  try {
    staging = await Directory.systemTemp.createTemp('call_logger_verify_');
    final extracted = File(
      p.join(staging.path, BuildingMapStorage.backupZipDbFileName),
    );
    await extracted.writeAsBytes(dbEntry.content as List<int>, flush: true);
    return await _verifyDatabaseFile(extracted.path);
  } catch (e) {
    return BackupVerificationResult(
      status: BackupVerificationStatus.inconclusive,
      message: 'Ο έλεγχος του αντιγράφου δεν ολοκληρώθηκε.',
      rawDetail: e.toString(),
    );
  } finally {
    if (staging != null) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {
        // Ένα προσωρινό αρχείο που δεν σβήστηκε δεν αλλάζει την ετυμηγορία,
        // και τα Windows το καθαρίζουν μόνα τους.
      }
    }
  }
}

/// Η ίδια η βάση: ανοίγει, και το SQLite τη βρίσκει συνεπή;
Future<BackupVerificationResult> _verifyDatabaseFile(String dbPath) async {
  final outcome = await runDatabaseIntegrityProbe(dbPath);
  switch (outcome.status) {
    case DatabaseIntegrityStatus.ok:
      return BackupVerificationResult.ok;
    case DatabaseIntegrityStatus.corrupt:
      return BackupVerificationResult(
        status: BackupVerificationStatus.corruptDatabase,
        message:
            'Η βάση μέσα στο αντίγραφο είναι χαλασμένη — το αντίγραφο δεν '
            'μπορεί να επαναφερθεί.',
        rawDetail: outcome.rawMessage,
      );
    case DatabaseIntegrityStatus.inconclusive:
      return BackupVerificationResult(
        status: BackupVerificationStatus.inconclusive,
        message: 'Ο έλεγχος του αντιγράφου δεν κατέληξε.',
        rawDetail: outcome.rawMessage,
      );
  }
}
