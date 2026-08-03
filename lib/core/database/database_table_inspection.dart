import 'package:sqflite_common/sqlite_api.dart' show DatabaseException;

import 'database_helper.dart';

/// Αποτέλεσμα προεπισκόπησης πίνακα: ονόματα στηλών και γραμμές (List<Map>).
class TablePreviewResult {
  const TablePreviewResult({required this.columns, required this.rows});

  final List<String> columns;
  final List<Map<String, dynamic>> rows;
}

/// Εργαλεία επιθεώρησης πινάκων (ονόματα, σχήμα, προεπισκόπηση).
///
/// Συνεργάτης του [DatabaseHelper] (Σύνθεση) — πρόσβαση μέσω
/// `DatabaseHelper.instance.tableInspection`.
class DatabaseTableInspection {
  const DatabaseTableInspection(this.helper);

  final DatabaseHelper helper;

  /// Λίστα ονομάτων πινάκων (χωρίς εσωτερικά sqlite_*). Για προβολή Βάσης Δεδομένων.
  Future<List<String>> getTableNames() async {
    final db = await helper.database;
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return r.map((e) => e['name'] as String).toList();
  }

  /// Επιστρέφει συμβολοσειρά σχήματος πίνακα: `όνομα ΤΥΠΟΣ, ...` (από PRAGMA table_info).
  Future<String> getTableSchema(String tableName) async {
    final db = await helper.database;
    final quoted = _sqliteQuoteIdentifier(tableName);
    final info = await db.rawQuery('PRAGMA table_info($quoted)');
    if (info.isEmpty) return '';
    final parts = <String>[];
    for (final row in info) {
      final colName = row['name'] as String? ?? '';
      final rawType = (row['type'] as String?)?.trim();
      final typeSuffix = (rawType == null || rawType.isEmpty)
          ? ''
          : ' $rawType';
      parts.add('$colName$typeSuffix');
    }
    return parts.join(', ');
  }

  /// Συνολικό πλήθος εγγραφών πίνακα (για ένδειξη «Χ από Ψ» στην προεπισκόπηση).
  Future<int> getTableRowCount(String tableName) async {
    final db = await helper.database;
    final quoted = _sqliteQuoteIdentifier(tableName);
    final q = await db.rawQuery('SELECT COUNT(*) AS c FROM $quoted');
    return (q.first['c'] as int?) ?? 0;
  }

  /// Προεπισκόπηση πίνακα: στήλες + μία σελίδα γραμμών ([rowLimit] από [offset]).
  /// Για προβολή τύπου Excel με σελιδοποίηση.
  Future<TablePreviewResult> getTablePreview(
    String tableName, {
    int rowLimit = 500,
    int offset = 0,
  }) async {
    final db = await helper.database;
    final quoted = _sqliteQuoteIdentifier(tableName);
    final info = await db.rawQuery('PRAGMA table_info($quoted)');
    final columns = (info
        .map((e) => e['name'] as String?)
        .whereType<String>()
        .toList());
    if (columns.isEmpty) return TablePreviewResult(columns: [], rows: []);

    // ORDER BY rowid: χωρίς ρητή σειρά η SQLite δεν εγγυάται σταθερότητα
    // μεταξύ σελίδων (κίνδυνος κενών/διπλοτύπων στη σελιδοποίηση).
    List<Map<String, dynamic>> rows;
    try {
      rows = await db.rawQuery(
        'SELECT * FROM $quoted ORDER BY rowid LIMIT $rowLimit OFFSET $offset',
      );
    } on DatabaseException {
      // Πίνακες WITHOUT ROWID δεν έχουν στήλη rowid.
      rows = await db.rawQuery(
        'SELECT * FROM $quoted LIMIT $rowLimit OFFSET $offset',
      );
    }
    return TablePreviewResult(columns: columns, rows: rows);
  }
}

String _sqliteQuoteIdentifier(String identifier) {
  return '"${identifier.replaceAll('"', '""')}"';
}
