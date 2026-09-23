import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

import 'database_busy_timeout.dart';

/// Πόσα bytes ταξιδεύουν σε κάθε ανάγνωση του στιγμιότυπου.
///
/// Μετρημένο 23/09/2026 σε κοινόχρηστη βάση 13,7 MB με δεύτερο σταθμό
/// ανοιχτό: κομμάτια από 256 KB ως 4 MB έδωσαν 1,24–1,46 δευτερόλεπτα — το
/// όριο είναι η ταχύτητα του δικτύου, όχι το πλήθος των ταξιδιών. Το 1 MB
/// ήταν από τα καλύτερα και κρατά μικρό το αποτύπωμα μνήμης.
const int kDatabaseSnapshotChunkBytes = 1024 * 1024;

/// Τι κόστισε ένα στιγμιότυπο — για το ημερολόγιο, ώστε να φαίνεται στην
/// πράξη πόσο κράτησε το κλείδωμα σε κάθε μηχάνημα και δίκτυο.
class DatabaseSnapshotStats {
  const DatabaseSnapshotStats({required this.bytes, required this.lockHeld});

  final int bytes;

  /// Πόση ώρα οι άλλοι σταθμοί δεν μπορούσαν να ολοκληρώσουν εγγραφή.
  final Duration lockHeld;

  /// «17,0 MB, κλείδωμα 1,4 δευτ.» — γραμμένο για το ημερολόγιο εκκίνησης.
  String get summary {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');
    final seconds = (lockHeld.inMilliseconds / 1000)
        .toStringAsFixed(1)
        .replaceAll('.', ',');
    return 'στιγμιότυπο $mb MB, κλείδωμα $seconds δευτ.';
  }
}

/// Τοπικό αντίγραφο του αρχείου βάσης, πιστό τη στιγμή που πάρθηκε.
///
/// Ανήκει σε όποιον το ζήτησε: ο ίδιος καλεί [dispose] όταν τελειώσει.
class DatabaseSnapshot {
  DatabaseSnapshot._(this.path, this.stats, this._directory);

  /// Η διαδρομή του τοπικού αντιγράφου.
  final String path;
  final DatabaseSnapshotStats stats;
  final Directory _directory;

  Future<void> dispose() async {
    try {
      await _directory.delete(recursive: true);
    } catch (_) {
      // Ένα προσωρινό αρχείο που δεν σβήστηκε δεν αλλάζει κανένα αποτέλεσμα,
      // και τα Windows καθαρίζουν μόνα τους τον φάκελο των προσωρινών.
    }
  }
}

/// Η βάση δεν στέκει ολόκληρη μέσα στο κύριο αρχείο της (π.χ. WAL, μνήμη) —
/// το αντίγραφο του αρχείου δεν θα ήταν πιστό. Ο καλών ακολουθεί τον παλιό,
/// απευθείας δρόμο.
class DatabaseSnapshotUnsupported implements Exception {
  const DatabaseSnapshotUnsupported(this.journalMode);

  final String journalMode;

  @override
  String toString() =>
      'Η βάση είναι σε κατάσταση «$journalMode» — το στιγμιότυπο δεν εφαρμόζεται.';
}

/// Τρόποι ημερολογίου όπου ολόκληρη η βάση ζει μέσα στο κύριο αρχείο.
const Set<String> _selfContainedJournalModes = {
  'delete',
  'truncate',
  'persist',
};

/// Άνοιγμα μόνο για ανάγνωση, με την αναμονή κλειδώματος της διαδρομής.
///
/// Σε κοινόχρηστη βάση ακόμη και η ανάγνωση συναντά κλειδώματα: χωρίς
/// αναμονή, κάθε εγγραφή κάποιου συναδέλφου θα έκανε τον έλεγχο να
/// αποτύχει. Χωρίς `version:` — αλλιώς το sqflite επιχειρεί
/// `PRAGMA user_version = N` σε σύνδεση μόνο-ανάγνωσης.
Future<Database> openDatabaseReadOnlyWithBusyTimeout(String path) =>
    openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
      onConfigure: (db) => applyDatabaseBusyTimeout(db, path),
    );

/// Αντιγράφει το αρχείο [dbPath] σε τοπικό προσωρινό φάκελο, πιστά.
///
/// **Γιατί υπάρχει.** Όσο ένας μόνο υπολογιστής έχει ανοιχτή μια κοινόχρηστη
/// βάση, τα Windows κρατούν το αρχείο στη μνήμη. Μόλις την ανοίξει και
/// δεύτερος, σταματούν — και κάθε σελίδα των 4 KB που ζητά το SQLite γίνεται
/// ξεχωριστό ταξίδι στο δίκτυο. Μετρημένο 23/09/2026 σε βάση 13,7 MB: ο
/// έλεγχος ακεραιότητας πήγε από 0,03 σε **20 δευτερόλεπτα**, και το αντίγραφο
/// ασφαλείας κρατούσε τη βάση κλειδωμένη **12 δευτερόλεπτα** για όλους. Με
/// μεγάλα κομμάτια το ίδιο αρχείο αντιγράφεται σε ~1,3 δευτερόλεπτα, και ο
/// βαρύς έλεγχος γίνεται μετά τοπικά, σε χιλιοστά.
///
/// **Γιατί είναι πιστό.** Όσο διαρκεί η αντιγραφή κρατιέται το ίδιο κλείδωμα
/// ανάγνωσης που παίρνει κάθε απλή ανάγνωση: οι άλλοι διαβάζουν κανονικά,
/// αλλά κανείς δεν ολοκληρώνει εγγραφή στη μέση. Και μια εγγραφή που έμεινε
/// μισή από κατάρρευση αναιρείται από το ίδιο το SQLite **πριν** δοθεί το
/// κλείδωμα — ή, σε σύνδεση μόνο-ανάγνωσης, αρνείται να το δώσει.
///
/// **Δεν κρεμάει.** Με [deadline], η αντιγραφή σταματά ανάμεσα σε δύο
/// κομμάτια, αφήνει το κλείδωμα και σβήνει ό,τι έγραψε — ένα όριο που
/// σταματά μόνο την αναμονή και αφήνει τη δουλειά να τρέχει από πίσω θα
/// έστηνε ουρά μπροστά σε κάθε επόμενο βήμα.
///
/// Πετά [DatabaseSnapshotUnsupported] όταν η βάση δεν ζει ολόκληρη στο κύριο
/// αρχείο της (WAL, μνήμη).
Future<DatabaseSnapshot> takeDatabaseSnapshot(
  String dbPath, {
  Future<Database> Function(String path) openSource =
      openDatabaseReadOnlyWithBusyTimeout,
  DateTime? deadline,
  int chunkSize = kDatabaseSnapshotChunkBytes,
  DateTime Function() now = DateTime.now,
  @visibleForTesting Future<void> Function()? whileLocked,
}) async {
  void checkDeadline() {
    if (deadline != null && now().isAfter(deadline)) {
      throw TimeoutException('Το στιγμιότυπο της βάσης δεν πρόλαβε.');
    }
  }

  final source = await openSource(dbPath);
  Directory? directory;
  var inTransaction = false;
  try {
    await source.execute('BEGIN');
    inTransaction = true;
    // Η πρώτη ανάγνωση παίρνει το κλείδωμα ανάγνωσης — και απορρίπτει ό,τι
    // δεν είναι βάση («file is not a database») πριν αντιγραφεί οτιδήποτε.
    await source.rawQuery('SELECT count(*) FROM sqlite_master');
    final lockWatch = Stopwatch()..start();

    final modeRows = await source.rawQuery('PRAGMA journal_mode');
    final mode = modeRows.isEmpty
        ? ''
        : '${modeRows.first.values.first ?? ''}'.trim().toLowerCase();
    if (!_selfContainedJournalModes.contains(mode)) {
      throw DatabaseSnapshotUnsupported(mode);
    }
    checkDeadline();
    await whileLocked?.call();

    directory = await Directory.systemTemp.createTemp('call_logger_snapshot_');
    final localPath = p.join(directory.path, 'snapshot.db');
    final bytes = await _copyInChunks(
      dbPath,
      localPath,
      chunkSize: chunkSize,
      checkDeadline: checkDeadline,
    );

    await source.execute('COMMIT');
    inTransaction = false;
    lockWatch.stop();

    final snapshot = DatabaseSnapshot._(
      localPath,
      DatabaseSnapshotStats(bytes: bytes, lockHeld: lockWatch.elapsed),
      directory,
    );
    directory = null; // ανήκει πλέον στον καλούντα
    return snapshot;
  } finally {
    if (inTransaction) {
      try {
        await source.execute('COMMIT');
      } catch (_) {}
    }
    try {
      await source.close();
    } catch (_) {}
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
    }
  }
}

Future<int> _copyInChunks(
  String sourcePath,
  String targetPath, {
  required int chunkSize,
  required void Function() checkDeadline,
}) async {
  final input = await File(sourcePath).open();
  RandomAccessFile? output;
  var total = 0;
  try {
    output = await File(targetPath).open(mode: FileMode.writeOnly);
    while (true) {
      final chunk = await input.read(chunkSize);
      if (chunk.isEmpty) break;
      await output.writeFrom(chunk);
      total += chunk.length;
      checkDeadline();
    }
    await output.flush();
    return total;
  } finally {
    await input.close();
    await output?.close();
  }
}
