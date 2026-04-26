import '../database_helper.dart' show TablePreviewResult;
import 'lamp_database_provider.dart';
import 'lamp_table_greek_names.dart';

/// Ιδιοτική χρήση: απόδραση αναγνωριστικού SQL (ίδιο μοτίβο με [DatabaseHelper]).
String lampSqliteQuoteIdentifier(String identifier) {
  return '"${identifier.replaceAll('"', '""')}"';
}

class LampTableBrowserApi {
  LampTableBrowserApi._();
  static final LampTableBrowserApi instance = LampTableBrowserApi._();

  final LampDatabaseProvider _provider = LampDatabaseProvider.instance;

  Future<List<String>> getTableNames(String path) async {
    final db = await _provider.open(
      path.trim(),
      mode: LampDatabaseMode.read,
    );
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return r.map((e) => e['name'] as String).toList();
  }

  Future<int> getTableRowCount(String path, String tableName) async {
    final db = await _provider.open(
      path.trim(),
      mode: LampDatabaseMode.read,
    );
    final q = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${lampSqliteQuoteIdentifier(tableName)}',
    );
    return (q.first['c'] as int?) ?? 0;
  }

  /// Άθροισμα [COUNT](*) ανά πίνακα, ένα `open` / σύνδεση.
  Future<LampFileTableSummary> getFileAndTableSummary(String path) async {
    final p = path.trim();
    final db = await _provider.open(p, mode: LampDatabaseMode.read);
    final nameRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final names = nameRows.map((e) => e['name'] as String).toList();
    var total = 0;
    final counts = <String, int>{};
    for (final n in names) {
      final q = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM ${lampSqliteQuoteIdentifier(n)}',
      );
      final c = (q.first['c'] as int?) ?? 0;
      counts[n] = c;
      total += c;
    }
    return LampFileTableSummary(
      tableNamesOrdered: lampOrderedTableNames(names),
      rowCountByTable: counts,
      totalRowCount: total,
    );
  }

  /// Προεπισκόπηση: στήλες + σειρές, χωρίς zoom/resize (απεικονίζει το widget).
  Future<TablePreviewResult> getTablePreview(
    String path,
    String tableName, {
    int rowLimit = 200,
  }) async {
    final db = await _provider.open(
      path.trim(),
      mode: LampDatabaseMode.read,
    );
    final quoted = lampSqliteQuoteIdentifier(tableName);
    final info = await db.rawQuery('PRAGMA table_info($quoted)');
    final columns = (info
        .map((e) => e['name'] as String?)
        .whereType<String>()
        .toList());
    if (columns.isEmpty) {
      return const TablePreviewResult(columns: [], rows: []);
    }
    final rows = await db.rawQuery(
      'SELECT * FROM $quoted LIMIT $rowLimit',
    );
    return TablePreviewResult(columns: columns, rows: rows);
  }
}

class LampFileTableSummary {
  const LampFileTableSummary({
    required this.tableNamesOrdered,
    required this.rowCountByTable,
    required this.totalRowCount,
  });

  final List<String> tableNamesOrdered;
  final Map<String, int> rowCountByTable;
  final int totalRowCount;
}
