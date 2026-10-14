import 'dart:io';

import 'package:path/path.dart' as p;

import 'log_file_names.dart';

/// Ποια αρχεία του φακέλου `logs` σβήνονται, και πότε.
///
/// Δεν κρίνει αν ο φάκελος απαντά ούτε βάζει όριο χρόνου: αυτά ανήκουν στον
/// κάτοχο του φακέλου (`CrashLogService`), που καλεί την εκκαθάριση μέσα στον
/// δικό του φρουρό.
abstract final class LogRetention {
  /// Κρατά τα [retentionCount] πιο πρόσφατα ημερήσια αρχεία — δηλαδή τις
  /// τελευταίες τόσες **ημέρες με καταγραφές**. Ένας υπολογιστής που έμεινε
  /// κλειστός μια εβδομάδα δεν χάνει έτσι το ιστορικό του.
  ///
  /// Τα αρχεία της παλιάς μορφής δεν πληθαίνουν πια, οπότε δεν θα έφταναν
  /// ποτέ το όριο πλήθους: σβήνονται όταν γίνουν παλαιότερα από τόσες
  /// ημερολογιακές ημέρες.
  ///
  /// Μαζεύει επίσης τα αρχεία ιχνηλάτησης κλεισίματος της παλιάς εποχής, όταν
  /// το κάθε περιστατικό έπαιρνε δικό του αρχείο. Πλέον προσαρτώνται στο
  /// αρχείο συνεδρίας της ημέρας τους, οπότε όσα έμειναν δεν τα διαβάζει
  /// κανείς — και χωρίς αυτή τη γραμμή δεν θα τα έσβηνε ποτέ κανείς.
  static Future<void> purge({
    required String logsDirectory,
    required int retentionCount,
    required DateTime Function() now,
  }) async {
    final dir = Directory(logsDirectory);
    if (!await dir.exists()) return;

    final entries = await dir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    await _purgeDailyLogs(entries, retentionCount);
    await _purgeLegacyDailyLogs(entries, retentionCount, now);
    await _purgeLegacyShutdownTraces(entries);
  }

  static Future<void> _purgeLegacyDailyLogs(
    List<File> entries,
    int retentionCount,
    DateTime Function() now,
  ) async {
    final today = now();
    final oldestKept = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: retentionCount - 1));
    for (final file in entries) {
      final name = p.basename(file.path);
      if (!LogFileNames.isLegacyDailyLogFileName(name)) continue;
      final day = LogFileNames.dayOfLogFile(name);
      if (day == null || !day.isBefore(oldestKept)) continue;
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static Future<void> _purgeDailyLogs(
    List<File> entries,
    int retentionCount,
  ) async {
    final files = entries
        .where((file) => LogFileNames.isDailyLogFileName(p.basename(file.path)))
        .toList();
    if (files.length <= retentionCount) return;

    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final file in files.skip(retentionCount)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  /// Σβήνει **μόνο** τα αρχεία περιστατικών της παλιάς εποχής — αυτά που
  /// φέρουν ημερομηνία στο όνομά τους.
  ///
  /// Τα προσωρινά ίχνη εργασίας δεν αγγίζονται ποτέ, ούτε τα δικά μας ούτε
  /// άλλου σταθμού: όταν υπάρχουν, είτε ανήκουν σε κλείσιμο που πέθανε στη
  /// μέση και περιμένει να προαχθεί, είτε — σε κοινόχρηστο φάκελο — σε
  /// υπολογιστή που **αυτή τη στιγμή** κλείνει.
  static Future<void> _purgeLegacyShutdownTraces(List<File> entries) async {
    for (final file in entries) {
      if (!LogFileNames.isLegacyShutdownIncidentFileName(
        p.basename(file.path),
      )) {
        continue;
      }
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
