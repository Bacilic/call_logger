import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/database_backup_settings.dart';

/// Τι έμεινε πίσω από μια εκκαθάριση.
class BackupRetentionOutcome {
  const BackupRetentionOutcome({
    this.heldBackByAge = 0,
    this.previousQuickCopies = 0,
    this.notDeleted = const [],
  });

  /// Πόσα γρήγορα αντίγραφα κράτησε ο φρουρός του ορίου ηλικίας.
  final int heldBackByAge;

  /// Από πόσα προηγούμενα γρήγορα αντίγραφα.
  final int previousQuickCopies;

  /// Τα αρχεία που έπρεπε να σβηστούν και αρνήθηκαν.
  final List<String> notDeleted;

  /// Όσα πρέπει να μάθει ο χρήστης· άδειο στην κανονική περίπτωση.
  List<String> get notes => [
    if (heldBackByAge > 0)
      'Τα παλιά αντίγραφα δεν σβήστηκαν, γιατί το όριο ηλικίας θα έσβηνε '
          'μονομιάς $heldBackByAge από τα $previousQuickCopies. Ελέγξτε ότι η '
          'ώρα του υπολογιστή είναι σωστή.',
    if (notDeleted.isNotEmpty)
      'Δεν σβήστηκαν ${notDeleted.length} παλιά αντίγραφα, ίσως επειδή είναι '
          'ανοιχτά σε άλλο πρόγραμμα: ${notDeleted.join(', ')}.',
  ];
}

/// Πολιτική διατήρησης δύο γραμμών (Φάση 6): τα γρήγορα αντίγραφα (`.db`,
/// μόνο βάση) και τα πλήρη (`.zip`, βάση + φορητά) έχουν χωριστά όρια —
/// τα γρήγορα είναι πολλά και μικρής ζωής, τα πλήρη λίγα και πολύτιμα.
///
/// **Απαράβατος κανόνας: το πιο πρόσφατο πλήρες δεν διαγράφεται ΠΟΤΕ**, ό,τι
/// κι αν λένε τα όρια — χωρίς αυτό, μια επιθετική ρύθμιση θα άφηνε τη βάση
/// χωρίς κανένα αντίγραφο των φορητών.
///
/// **Λάθος ρολόι δεν σβήνει αντίγραφα.** Δεύτερο ρολόι για σύγκριση δεν
/// υπάρχει, οπότε κρίνεται το αποτέλεσμα και όχι η ώρα:
/// - το αντίγραφο που μόλις έγινε δεν σβήνεται ποτέ, όποια ώρα κι αν γράφει·
/// - αν το όριο ηλικίας θα έσβηνε μονομιάς πάνω από τα μισά προηγούμενα
///   γρήγορα, δεν σβήνει κανένα. Στην κανονική χρήση φεύγουν λίγα κάθε φορά,
///   οπότε ο φρουρός πιάνει και τον σταθμό που έμεινε κλειστός για μέρες.
abstract final class BackupRetention {
  static Future<BackupRetentionOutcome> apply({
    required Directory destDir,
    required String baseName,
    required DatabaseBackupSettings settings,
    required String justCreatedPath,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final escapedBase = RegExp.escape(baseName);
    final dateFirst = RegExp(
      '^(\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2})_$escapedBase\\.(db|zip)\$',
    );
    final baseFirst = RegExp(
      '^${escapedBase}_(\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2})\\.(db|zip)\$',
    );

    final quick = <File>[];
    final full = <File>[];
    await for (final entity in destDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!dateFirst.hasMatch(name) && !baseFirst.hasMatch(name)) continue;
      if (name.toLowerCase().endsWith('.zip')) {
        full.add(entity);
      } else {
        quick.add(entity);
      }
    }

    // ── Γρήγορα (.db): ηλικία και πλήθος ─────────────────────────────────
    final justCreatedName = p.basename(justCreatedPath);
    bool isJustCreated(File f) => p.basename(f.path) == justCreatedName;
    final notDeleted = <String>[];
    Future<void> tryDelete(File f) async {
      if (isJustCreated(f)) return;
      try {
        await f.delete();
      } catch (_) {
        notDeleted.add(p.basename(f.path));
      }
    }

    var quickRemaining = List<File>.from(quick);
    var heldBackByAge = 0;
    var previousQuickCopies = 0;
    if (settings.retentionQuickMaxAgeEnabled) {
      final cutoff = current.subtract(
        Duration(days: settings.retentionQuickMaxAgeDays),
      );
      final previous = quick.where((f) => !isJustCreated(f)).toList();
      final tooOld = <File>[];
      for (final f in previous) {
        try {
          final stat = await f.stat();
          if (stat.modified.isBefore(cutoff)) tooOld.add(f);
        } catch (_) {
          // Ό,τι δεν διαβάζεται δεν κρίνεται παλιό.
        }
      }
      if (tooOld.length * 2 > previous.length) {
        heldBackByAge = tooOld.length;
        previousQuickCopies = previous.length;
      } else {
        for (final f in tooOld) {
          await tryDelete(f);
        }
        quickRemaining = quick.where((f) => !tooOld.contains(f)).toList();
      }
    }
    if (settings.retentionQuickMaxCopiesEnabled &&
        quickRemaining.length > settings.retentionQuickMaxCopies) {
      _sortNewestFirst(quickRemaining);
      for (final f in quickRemaining.skip(settings.retentionQuickMaxCopies)) {
        await tryDelete(f);
      }
    }

    // ── Πλήρη (.zip): πλήθος, με άθικτο πάντα το πιο πρόσφατο ────────────
    if (settings.retentionFullMaxCopiesEnabled && full.length > 1) {
      _sortNewestFirst(full);
      final keep = settings.retentionFullMaxCopies < 1
          ? 1
          : settings.retentionFullMaxCopies;
      for (final f in full.skip(keep)) {
        await tryDelete(f);
      }
    }
    return BackupRetentionOutcome(
      heldBackByAge: heldBackByAge,
      previousQuickCopies: previousQuickCopies,
      notDeleted: notDeleted,
    );
  }

  static void _sortNewestFirst(List<File> files) {
    files.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });
  }
}
