import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/database_backup_settings.dart';

/// Πολιτική διατήρησης δύο γραμμών (Φάση 6): τα γρήγορα αντίγραφα (`.db`,
/// μόνο βάση) και τα πλήρη (`.zip`, βάση + φορητά) έχουν χωριστά όρια —
/// τα γρήγορα είναι πολλά και μικρής ζωής, τα πλήρη λίγα και πολύτιμα.
///
/// **Απαράβατος κανόνας: το πιο πρόσφατο πλήρες δεν διαγράφεται ΠΟΤΕ**, ό,τι
/// κι αν λένε τα όρια — χωρίς αυτό, μια επιθετική ρύθμιση θα άφηνε τη βάση
/// χωρίς κανένα αντίγραφο των φορητών.
abstract final class BackupRetention {
  static Future<void> apply({
    required Directory destDir,
    required String baseName,
    required DatabaseBackupSettings settings,
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
    var quickRemaining = List<File>.from(quick);
    if (settings.retentionQuickMaxAgeEnabled) {
      final cutoff = current.subtract(
        Duration(days: settings.retentionQuickMaxAgeDays),
      );
      final survivors = <File>[];
      for (final f in quickRemaining) {
        try {
          final stat = await f.stat();
          if (stat.modified.isBefore(cutoff)) {
            await f.delete();
          } else {
            survivors.add(f);
          }
        } catch (_) {
          survivors.add(f);
        }
      }
      quickRemaining = survivors;
    }
    if (settings.retentionQuickMaxCopiesEnabled &&
        quickRemaining.length > settings.retentionQuickMaxCopies) {
      _sortNewestFirst(quickRemaining);
      for (final f in quickRemaining.skip(settings.retentionQuickMaxCopies)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    // ── Πλήρη (.zip): πλήθος, με άθικτο πάντα το πιο πρόσφατο ────────────
    if (settings.retentionFullMaxCopiesEnabled && full.length > 1) {
      _sortNewestFirst(full);
      final keep = settings.retentionFullMaxCopies < 1
          ? 1
          : settings.retentionFullMaxCopies;
      for (final f in full.skip(keep)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
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
