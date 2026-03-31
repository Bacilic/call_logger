import 'package:flutter/foundation.dart';

/// Στιγμιότυπο στατιστικών αρχείου βάσης και μετρήσεων πινάκων (για οθόνη περιήγησης).
@immutable
class DatabaseStats {
  const DatabaseStats({
    required this.fileSizeBytes,
    required this.dbPath,
    required this.rowCountsByTable,
    this.lastBackupTime,
  });

  /// Μέγεθος αρχείου `.db` σε byte (από [File.length]).
  final int fileSizeBytes;

  /// Απόλυτη διαδρομή αρχείου βάσης.
  final String dbPath;

  /// Χρονική σήμανση τελευταίου αρχείου αντιγράφου στον φάκελο προορισμού (αν υπάρχει).
  final DateTime? lastBackupTime;

  /// `όνομα_πίνακα` → πλήθος εγγραφών (`COUNT(*)`).
  final Map<String, int> rowCountsByTable;

  int rowCountForTable(String tableName) =>
      rowCountsByTable[tableName] ?? 0;
}
