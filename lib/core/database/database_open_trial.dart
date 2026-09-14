/// Δοκιμαστικό άνοιγμα βάσης — η μόνη απόδειξη ότι ένα αρχείο ανοίγει.
///
/// **Το πρόβλημα που λύνει (14/09/2026):** ο κριτής της επαναφοράς αποφάσιζε
/// με τα **ονόματα** επτά πινάκων και έναν αριθμό έκδοσης. Το άνοιγμα όμως
/// αποφασίζει με κάτι άλλο: αν θα **δημιουργήσει** σχήμα ή θα το
/// **αναβαθμίσει**. Δύο αρχεία που περνούσαν τον κριτή έριχναν την εφαρμογή
/// αμέσως μετά — αφού είχαν ήδη αντικαταστήσει τη βάση εργασίας:
///
/// - αρχείο με ετικέτα έκδοσης **0** και πλήρεις πίνακες: το άνοιγμα το
///   περνά για καινούριο και προσπαθεί να φτιάξει από την αρχή πίνακες που
///   ήδη υπάρχουν (`table calls already exists`)·
/// - αρχείο με ετικέτα **17** και σχήμα που δεν είναι του 17: τρέχουν οι
///   μεταπτώσεις 18→60 και ζητούν πίνακες που λείπουν
///   (`no such table: audit_log`).
///
/// **Ο κανόνας:** κανένα αρχείο δεν κρίνεται κατάλληλο πριν **ανοίξει
/// πραγματικά** με το σχήμα αυτής της εφαρμογής. Το άνοιγμα γίνεται σε
/// **αντίγραφο** σε προσωρινό φάκελο: το πρωτότυπο δεν αγγίζεται ποτέ, ώστε
/// ούτε να αναβαθμιστεί κρυφά ούτε να μείνει μισοαλλαγμένο αν η δοκιμή σκάσει.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_schema_migrations.dart';

/// Τι απάντησε η δοκιμή.
enum DatabaseOpenTrialStatus {
  /// Το αρχείο άνοιξε ως το τέλος, με δημιουργία ή μεταπτώσεις όπως χρειάστηκε.
  opens,

  /// Το άνοιγμα σταμάτησε με σφάλμα — **απόδειξη** ότι δεν ανοίγει ούτε στα
  /// αλήθεια.
  fails,

  /// Η δοκιμή δεν ολοκληρώθηκε (δεν αντιγράφηκε, άργησε πολύ). Δεν είναι
  /// απόδειξη τίποτα, και ποτέ δεν εμποδίζει από μόνη της.
  inconclusive,
}

/// Το αποτέλεσμα μιας δοκιμής, μαζί με ό,τι χρειάζεται η οθόνη για να το πει.
class DatabaseOpenTrial {
  const DatabaseOpenTrial.opens()
    : status = DatabaseOpenTrialStatus.opens,
      reason = null,
      technicalDetail = null;

  const DatabaseOpenTrial.fails(this.reason, {this.technicalDetail})
    : status = DatabaseOpenTrialStatus.fails;

  const DatabaseOpenTrial.inconclusive({this.technicalDetail})
    : status = DatabaseOpenTrialStatus.inconclusive,
      reason = null;

  final DatabaseOpenTrialStatus status;

  /// Μία καθαρή ελληνική πρόταση για τον χρήστη. `null` όταν δεν απέτυχε.
  final String? reason;

  /// Το ωμό κείμενο του SQLite. Δεν μπαίνει ποτέ στο [reason] — ζει πίσω από
  /// τις «Τεχνικές λεπτομέρειες», ένα πάτημα μακριά.
  final String? technicalDetail;

  /// `true` μόνο με **απόδειξη** αποτυχίας — ποτέ από σιωπή ή καθυστέρηση.
  bool get provenToFail => status == DatabaseOpenTrialStatus.fails;
}

/// Πόσο περιμένουμε μια μετάπτωση πριν πούμε «δεν ξέρω».
///
/// Μεγάλη βάση σε αργό δίσκο μπορεί να θέλει λεπτά· η υπέρβαση **δεν**
/// καταδικάζει το αρχείο, γιατί αργή μετάπτωση και σπασμένη μετάπτωση δεν
/// είναι το ίδιο πράγμα.
const Duration kDatabaseOpenTrialTimeout = Duration(minutes: 3);

/// Ανοίγει **αντίγραφο** του [dbPath] ακριβώς όπως θα το άνοιγε η εφαρμογή.
///
/// Η μόνη σκόπιμη διαφορά από το πραγματικό άνοιγμα είναι οι ρυθμίσεις
/// σύνδεσης (χρόνος αναμονής, τρόπος ημερολογίου): αφορούν κοινή χρήση σε
/// δίκτυο, όχι το σχήμα, και το αντίγραφο είναι ούτως ή άλλως μόνο δικό μας.
Future<DatabaseOpenTrial> trialOpenDatabase(
  String dbPath, {
  int appSchemaVersion = kDatabaseSchemaVersion,
}) async {
  Directory? sandbox;
  try {
    sandbox = await Directory.systemTemp.createTemp('db-open-trial-');
    final copyPath = p.join(sandbox.path, p.basename(dbPath));
    await File(dbPath).copy(copyPath);

    final declaredVersion = await _readDeclaredVersion(copyPath);

    try {
      final db = await openDatabase(
        copyPath,
        version: appSchemaVersion,
        onCreate: onDatabaseCreate,
        onUpgrade: onDatabaseUpgradeSquashed,
        onDowngrade: onDatabaseDowngradeSquashed,
        singleInstance: false,
      ).timeout(kDatabaseOpenTrialTimeout);
      await db.close();
      return const DatabaseOpenTrial.opens();
    } on TimeoutException catch (e) {
      return DatabaseOpenTrial.inconclusive(technicalDetail: '$e');
    } catch (e) {
      return DatabaseOpenTrial.fails(
        databaseOpenTrialReason(
          declaredVersion: declaredVersion,
          appSchemaVersion: appSchemaVersion,
        ),
        technicalDetail: '$e',
      );
    }
  } catch (e) {
    // Αποτυχία αντιγραφής ή προσωρινού φακέλου: δεν μάθαμε τίποτα για το
    // αρχείο, και δεν το κατηγορούμε γι' αυτό.
    return DatabaseOpenTrial.inconclusive(technicalDetail: '$e');
  } finally {
    if (sandbox != null) {
      try {
        await sandbox.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Γιατί δεν ανοίγει, σε μία πρόταση που διαβάζεται από χειριστή.
///
/// Η αιτιολόγηση βγαίνει από **γνωστά γεγονότα** (τι έκδοση δηλώνει το ίδιο
/// το αρχείο, τι έκδοση διαβάζει η εφαρμογή) και ποτέ από το κείμενο του
/// σφάλματος: το ωμό μήνυμα του SQLite αλλάζει από μετάπτωση σε μετάπτωση και
/// δεν λέει τίποτα σε όποιον δεν γράφει κώδικα.
String databaseOpenTrialReason({
  required int? declaredVersion,
  required int appSchemaVersion,
}) {
  const advice = ' Δοκιμάστε άλλο, παλαιότερο αντίγραφο.';

  if (declaredVersion == null || declaredVersion <= 0) {
    return 'Το αρχείο περιέχει ήδη τους πίνακες της εφαρμογής αλλά δεν '
        'δηλώνει έκδοση σχήματος. Το άνοιγμα το εκλαμβάνει ως καινούρια '
        'βάση και σταματά προσπαθώντας να ξαναφτιάξει ό,τι υπάρχει.$advice';
  }
  if (declaredVersion < appSchemaVersion) {
    return 'Το σχήμα του αρχείου δεν αντιστοιχεί στην έκδοση '
        '$declaredVersion που δηλώνει το ίδιο. Η αναβάθμιση στην έκδοση '
        '$appSchemaVersion σταματά με σφάλμα.$advice';
  }
  return 'Το αρχείο δηλώνει την έκδοση σχήματος $declaredVersion αλλά δεν '
      'ανοίγει με αυτήν.$advice';
}

/// Την έκδοση τη ρωτάμε στο **αντίγραφο**, με άνοιγμα μόνο για ανάγνωση.
Future<int?> _readDeclaredVersion(String path) async {
  Database? db;
  try {
    db = await openDatabase(path, readOnly: true, singleInstance: false);
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) return null;
    return rows.first['user_version'] as int?;
  } catch (_) {
    return null;
  } finally {
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {}
    }
  }
}
