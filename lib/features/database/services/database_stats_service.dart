import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart';
import '../models/database_backup_settings.dart';
import '../models/database_stats.dart';

/// Συλλογή στατιστικών αρχείου βάσης και `COUNT(*)` ανά πίνακα.
class DatabaseStatsService {
  DatabaseStatsService._();

  static String _quoteId(String tableName) =>
      '"${tableName.replaceAll('"', '""')}"';

  /// Εμφάνιση μεγέθους αρχείου (π.χ. `4.8 MB`).
  static String formatFileSizeBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) {
      final s = kb >= 100 ? kb.toStringAsFixed(0) : kb.toStringAsFixed(1);
      return '$s KB';
    }
    final mb = kb / 1024;
    final s = mb >= 10 ? mb.toStringAsFixed(1) : mb.toStringAsFixed(2);
    return '$s MB';
  }

  /// Ακέραιος με διαχωριστικό χιλιάδων `.` (π.χ. `2.847`).
  static String formatIntegerEl(int value) {
    final s = value.abs().toString();
    final lead = s.length % 3;
    final parts = <String>[];
    if (lead > 0) {
      parts.add(s.substring(0, lead));
    }
    for (var i = lead; i < s.length; i += 3) {
      parts.add(s.substring(i, i + 3));
    }
    return parts.join('.');
  }

  /// Ίδια μορφή αρχείων αντιγράφου με [DatabaseBackupService] (κρατήσεις / ονοματολογία).
  static Future<DateTime?> latestBackupFileModified({
    required String destinationDirectory,
    required String dbBaseName,
  }) async {
    final dest = destinationDirectory.trim();
    if (dest.isEmpty) return null;
    final destDir = Directory(dest);
    if (!await destDir.exists()) return null;

    final escapedBase = RegExp.escape(dbBaseName);
    final dateFirst = RegExp(
      r'^(\d{4}-\d{2}-\d{2}_\d{2}-\d{2})_' + escapedBase + r'\.(db|zip)$',
    );
    final baseFirst = RegExp(
      r'^' + escapedBase + r'_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2})\.(db|zip)$',
    );

    DateTime? newest;
    await for (final entity in destDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!dateFirst.hasMatch(name) && !baseFirst.hasMatch(name)) continue;
      try {
        final t = await entity.lastModified();
        if (newest == null || t.isAfter(newest)) newest = t;
      } catch (_) {}
    }
    return newest;
  }

  static Future<DatabaseStats> getDatabaseStats() async {
    final db = await DatabaseHelper.instance.database;
    final dbPath = db.path;

    var fileSizeBytes = 0;
    try {
      final f = File(dbPath);
      if (await f.exists()) {
        fileSizeBytes = await f.length();
      }
    } catch (_) {}

    final tableNames = await DatabaseHelper.instance.getTableNames();
    final rowCounts = <String, int>{};
    for (final name in tableNames) {
      final q = _quoteId(name);
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $q');
      final n = r.first['c'];
      final count = n is int ? n : int.tryParse(n.toString()) ?? 0;
      rowCounts[name] = count;
    }

    final baseName = p.basenameWithoutExtension(dbPath);
    DateTime? lastBackup;

    try {
      final raw = await DatabaseHelper.instance
          .getSetting(DatabaseBackupSettings.appSettingsKey);
      final settings = DatabaseBackupSettings.fromJsonString(raw);
      lastBackup = await latestBackupFileModified(
        destinationDirectory: settings.destinationDirectory,
        dbBaseName: baseName,
      );
    } catch (_) {}

    return DatabaseStats(
      fileSizeBytes: fileSizeBytes,
      dbPath: dbPath,
      rowCountsByTable: rowCounts,
      lastBackupTime: lastBackup,
    );
  }
}
