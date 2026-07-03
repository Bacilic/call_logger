part of 'database_helper.dart';

/// Εργαλεία επιθεώρησης πινάκων (ονόματα, σχήμα, προεπισκόπηση).
mixin DatabaseTableInspectionMixin {
  DatabaseHelper get _inspectionHost => this as DatabaseHelper;

  /// Λίστα ονομάτων πινάκων (χωρίς εσωτερικά sqlite_*). Για προβολή Βάσης Δεδομένων.
  Future<List<String>> getTableNames() async {
    final db = await _inspectionHost.database;
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return r.map((e) => e['name'] as String).toList();
  }

  /// Επιστρέφει συμβολοσειρά σχήματος πίνακα: `όνομα ΤΥΠΟΣ, ...` (από PRAGMA table_info).
  Future<String> getTableSchema(String tableName) async {
    final db = await _inspectionHost.database;
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

  /// Προεπισκόπηση πίνακα: στήλες + γραμμές (μέγ. [rowLimit]). Για προβολή τύπου Excel.
  Future<TablePreviewResult> getTablePreview(
    String tableName, {
    int rowLimit = 500,
  }) async {
    final db = await _inspectionHost.database;
    final quoted = _sqliteQuoteIdentifier(tableName);
    final info = await db.rawQuery('PRAGMA table_info($quoted)');
    final columns = (info
        .map((e) => e['name'] as String?)
        .whereType<String>()
        .toList());
    if (columns.isEmpty) return TablePreviewResult(columns: [], rows: []);

    final rows = await db.rawQuery('SELECT * FROM $quoted LIMIT $rowLimit');
    return TablePreviewResult(columns: columns, rows: rows);
  }
}

String _sqliteQuoteIdentifier(String identifier) {
  return '"${identifier.replaceAll('"', '""')}"';
}
