import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'old_database_schema.dart';

class LampImportException implements Exception {
  const LampImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LampImportProgress {
  const LampImportProgress(this.message, {this.done = 0, this.total = 0});

  final String message;
  final int done;
  final int total;
}

class LampImportResult {
  const LampImportResult({
    required this.databasePath,
    required this.importedRows,
    required this.issueCount,
  });

  final String databasePath;
  final Map<String, int> importedRows;
  final int issueCount;
}

typedef LampImportProgressCallback = void Function(LampImportProgress progress);

class OldExcelImporter {
  Future<LampImportResult> importExcel({
    required String excelPath,
    required String databasePath,
    LampImportProgressCallback? onProgress,
  }) async {
    final input = File(excelPath);
    if (!await input.exists()) {
      throw const LampImportException('Δεν βρέθηκε το αρχείο Excel.');
    }

    final output = File(databasePath);
    if (!await output.parent.exists()) {
      await output.parent.create(recursive: true);
    }
    if (await output.exists()) {
      await output.delete();
    }

    final db = await openDatabase(databasePath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);

      final ext = p.extension(excelPath).toLowerCase();
      if (ext != '.xlsx' && ext != '.xls') {
        throw const LampImportException(
          'Υποστηρίζονται αρχεία .xlsx. Για .xls αποθηκεύστε ξανά ως .xlsx.',
        );
      }

      onProgress?.call(const LampImportProgress('Ανάγνωση Excel'));
      final Excel excel;
      try {
        excel = Excel.decodeBytes(await input.readAsBytes());
      } catch (_) {
        if (ext == '.xls') {
          await _insertIssue(
            db,
            sheet: 'workbook',
            rowNumber: null,
            columnName: null,
            rawValue: excelPath,
            issueType: 'xls_conversion_failed',
            message: 'Αποθηκεύστε το ως .xlsx από το Excel και δοκιμάστε ξανά.',
          );
          throw const LampImportException(
            'Αποθηκεύστε το ως .xlsx από το Excel και δοκιμάστε ξανά.',
          );
        }
        throw const LampImportException('Αποτυχία ανάγνωσης του Excel.');
      }
      final importedRows = <String, int>{};
      final issueBuffer = <_DataIssue>[];

      await db.execute('PRAGMA foreign_keys = OFF');
      await db.transaction((txn) async {
        final officeIds = await _importTable(
          txn,
          excel,
          _officesSpec,
          issueBuffer,
          onProgress,
        );
        importedRows['offices'] = officeIds.length;

        final ownerIds = await _importTable(
          txn,
          excel,
          _ownersSpec(officeIds),
          issueBuffer,
          onProgress,
        );
        importedRows['owners'] = ownerIds.length;

        final modelIds = await _importTable(
          txn,
          excel,
          _modelSpec,
          issueBuffer,
          onProgress,
        );
        importedRows['model'] = modelIds.length;

        final contractIds = await _importTable(
          txn,
          excel,
          _contractsSpec,
          issueBuffer,
          onProgress,
        );
        importedRows['contracts'] = contractIds.length;

        final equipmentIds = await _importTable(
          txn,
          excel,
          _equipmentSpec(modelIds, contractIds, ownerIds, officeIds),
          issueBuffer,
          onProgress,
        );
        importedRows['equipment'] = equipmentIds.length;

        for (final issue in issueBuffer) {
          await _insertIssue(txn, issue: issue);
        }
      });
      await db.execute('PRAGMA foreign_keys = ON');

      final issueRows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM data_issues',
      );
      final issueCount = (issueRows.first['count'] as int?) ?? 0;
      onProgress?.call(
        LampImportProgress('Ολοκληρώθηκε', done: issueCount, total: issueCount),
      );
      return LampImportResult(
        databasePath: databasePath,
        importedRows: importedRows,
        issueCount: issueCount,
      );
    } finally {
      await db.close();
    }
  }

  Future<Set<int>> _importTable(
    Transaction txn,
    Excel excel,
    _TableSpec spec,
    List<_DataIssue> issues,
    LampImportProgressCallback? onProgress,
  ) async {
    final sheet = _resolveSheet(excel, spec);
    if (sheet == null) {
      issues.add(
        _DataIssue(
          sheet: spec.table,
          issueType: 'missing_sheet',
          message: 'Δεν βρέθηκε φύλλο για τον πίνακα ${spec.table}.',
        ),
      );
      return <int>{};
    }

    final rows = sheet.rows;
    if (rows.isEmpty) return <int>{};
    final headerIndex = _findHeaderRow(rows);
    if (headerIndex == null) return <int>{};
    final headers = _headerIndexes(rows[headerIndex], spec);
    final records = <int, Map<String, Object?>>{};

    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNumber = i + 1;
      final values = <String, Object?>{};
      final rawValues = <String, String?>{};
      var hasAnyValue = false;

      for (final column in spec.columns) {
        final idx = headers[column.name];
        final cell = idx == null || idx >= row.length ? null : row[idx];
        final rawText = _cellText(cell);
        final value = _cellValue(cell, isDate: column.isDate);
        rawValues[column.name] = rawText;
        if (value != null) hasAnyValue = true;
        values[column.name] = value;
      }
      if (!hasAnyValue) continue;

      for (final fk in spec.foreignKeys) {
        final raw = rawValues[fk.column];
        final parsed = _parseInt(raw);
        final hasRaw = raw != null && raw.trim().isNotEmpty;
        if (fk.originalTextColumn != null) {
          values[fk.originalTextColumn!] = raw;
        }
        if (!hasRaw) {
          values[fk.column] = null;
          continue;
        }
        if (parsed != null && fk.validIds.contains(parsed)) {
          values[fk.column] = parsed;
        } else {
          values[fk.column] = null;
          issues.add(
            _DataIssue(
              sheet: sheet.sheetName,
              rowNumber: rowNumber,
              columnName: fk.column,
              rawValue: raw,
              issueType: parsed == null ? 'non_numeric_fk' : 'unknown_id',
              message: 'Η τιμή δεν αντιστοιχεί σε έγκυρο ID για ${fk.column}.',
            ),
          );
        }
      }

      for (final original in spec.alwaysOriginalTextColumns.entries) {
        values[original.value] = rawValues[original.key];
      }

      final id = _parseInt(rawValues[spec.primaryKey]);
      if (id == null) {
        issues.add(
          _DataIssue(
            sheet: sheet.sheetName,
            rowNumber: rowNumber,
            columnName: spec.primaryKey,
            rawValue: rawValues[spec.primaryKey],
            issueType: 'missing_primary_key',
            message: 'Παράλειψη γραμμής χωρίς έγκυρο primary key.',
          ),
        );
        continue;
      }
      values[spec.primaryKey] = id;

      if (records.containsKey(id)) {
        issues.add(
          _DataIssue(
            sheet: sheet.sheetName,
            rowNumber: rowNumber,
            columnName: spec.primaryKey,
            rawValue: id.toString(),
            issueType: 'duplicate_code_discarded',
            message:
                'Βρέθηκε διπλότυπο ${spec.primaryKey}. Κρατήθηκε η τελευταία εμφάνιση.',
          ),
        );
      }
      records[id] = values;

      if (i % 200 == 0) {
        onProgress?.call(
          LampImportProgress(
            'Ανάγνωση ${spec.table}',
            done: i - headerIndex,
            total: rows.length - headerIndex - 1,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (spec.table == 'equipment') {
      _normalizeEquipmentSetMaster(records, issues, sheet.sheetName);
    }

    for (final record in records.values) {
      await txn.insert(
        spec.table,
        record,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return records.keys.toSet();
  }

  void _normalizeEquipmentSetMaster(
    Map<int, Map<String, Object?>> records,
    List<_DataIssue> issues,
    String sheetName,
  ) {
    final equipmentIds = records.keys.toSet();
    for (final entry in records.entries) {
      final record = entry.value;
      final raw = record['set_master_original_text']?.toString();
      final parsed = _parseInt(raw);
      if (raw == null || raw.trim().isEmpty) {
        record['set_master'] = null;
        continue;
      }
      if (parsed != null && equipmentIds.contains(parsed)) {
        record['set_master'] = parsed;
        continue;
      }
      record['set_master'] = null;
      issues.add(
        _DataIssue(
          sheet: sheetName,
          rowNumber: null,
          columnName: 'set_master',
          rawValue: raw,
          issueType: parsed == null ? 'non_numeric_fk' : 'unknown_id',
          message: 'Το set_master δεν αντιστοιχεί σε έγκυρο code εξοπλισμού.',
        ),
      );
    }
  }

  Sheet? _resolveSheet(Excel excel, _TableSpec spec) {
    final entries = excel.tables.entries.toList();
    for (final entry in entries) {
      final normalized = _normalize(entry.key);
      if (spec.sheetAliases.any((alias) => normalized == _normalize(alias))) {
        return entry.value;
      }
    }
    for (final entry in entries) {
      final normalized = _normalize(entry.key);
      if (spec.sheetAliases.any(
        (alias) => normalized.contains(_normalize(alias)),
      )) {
        return entry.value;
      }
    }
    if (spec.fallbackSheetIndex >= 0 &&
        spec.fallbackSheetIndex < entries.length) {
      return entries[spec.fallbackSheetIndex].value;
    }
    return null;
  }

  int? _findHeaderRow(List<List<Data?>> rows) {
    for (var i = 0; i < rows.length && i < 10; i++) {
      final count = rows[i]
          .map(_cellText)
          .where((value) => value != null && value.trim().isNotEmpty)
          .length;
      if (count >= 2) return i;
    }
    return null;
  }

  Map<String, int> _headerIndexes(List<Data?> headerRow, _TableSpec spec) {
    final result = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final normalized = _normalize(_cellText(headerRow[i]) ?? '');
      if (normalized.isEmpty) continue;
      for (final column in spec.columns) {
        if (result.containsKey(column.name)) continue;
        final aliases = <String>{column.name, ...column.aliases};
        if (aliases.map(_normalize).contains(normalized)) {
          result[column.name] = i;
        }
      }
    }
    return result;
  }

  Object? _cellValue(Data? cell, {bool isDate = false}) {
    final text = _cellText(cell);
    if (text == null || text.trim().isEmpty || text.trim() == '-') return null;

    final value = cell?.value;
    if (isDate) {
      final date = _dateFromCellValue(value);
      if (date != null) {
        if (date.year == 1900) return null;
        return _formatDateTime(date);
      }
      return text;
    }
    return text;
  }

  String? _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return null;
    if (value is TextCellValue) return value.value.toString().trim();
    if (value is DateCellValue) {
      final dt = value.asDateTimeLocal();
      if (dt.year == 1900) return null;
      return _formatDateTime(dt);
    }
    if (value is DateTimeCellValue) {
      final dt = value.asDateTimeLocal();
      if (dt.year == 1900) return null;
      return _formatDateTime(dt);
    }
    final text = value.toString().trim();
    return text.isEmpty || text == '-' ? null : text;
  }

  DateTime? _dateFromCellValue(CellValue? value) {
    if (value is DateCellValue) return value.asDateTimeLocal();
    if (value is DateTimeCellValue) return value.asDateTimeLocal();
    return null;
  }

  int? _parseInt(String? value) {
    if (value == null) return null;
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return null;
    return int.tryParse(normalized) ??
        (double.tryParse(normalized)?.truncate() == double.tryParse(normalized)
            ? double.tryParse(normalized)?.toInt()
            : null);
  }

  String _formatDateTime(DateTime dt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-/().]+'), '');

  Future<void> _insertIssue(
    DatabaseExecutor db, {
    _DataIssue? issue,
    String? sheet,
    int? rowNumber,
    String? columnName,
    String? rawValue,
    String? issueType,
    String? message,
  }) async {
    final effective =
        issue ??
        _DataIssue(
          sheet: sheet,
          rowNumber: rowNumber,
          columnName: columnName,
          rawValue: rawValue,
          issueType: issueType ?? 'unknown',
          message: message,
        );
    await db.insert('data_issues', effective.toMap());
  }
}

class _TableSpec {
  const _TableSpec({
    required this.table,
    required this.primaryKey,
    required this.columns,
    required this.sheetAliases,
    required this.fallbackSheetIndex,
    this.foreignKeys = const <_ForeignKeySpec>[],
    this.alwaysOriginalTextColumns = const <String, String>{},
  });

  final String table;
  final String primaryKey;
  final List<_ColumnSpec> columns;
  final List<String> sheetAliases;
  final int fallbackSheetIndex;
  final List<_ForeignKeySpec> foreignKeys;
  final Map<String, String> alwaysOriginalTextColumns;
}

class _ColumnSpec {
  const _ColumnSpec(
    this.name, {
    this.aliases = const <String>[],
    this.isDate = false,
  });

  final String name;
  final List<String> aliases;
  final bool isDate;
}

class _ForeignKeySpec {
  const _ForeignKeySpec(this.column, this.validIds, {this.originalTextColumn});

  final String column;
  final Set<int> validIds;
  final String? originalTextColumn;
}

class _DataIssue {
  const _DataIssue({
    this.sheet,
    this.rowNumber,
    this.columnName,
    this.rawValue,
    required this.issueType,
    this.message,
  });

  final String? sheet;
  final int? rowNumber;
  final String? columnName;
  final String? rawValue;
  final String issueType;
  final String? message;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sheet': sheet,
      'row_number': rowNumber,
      'column_name': columnName,
      'raw_value': rawValue,
      'issue_type': issueType,
      'message': message,
      'created_at': DateTime.now().toIso8601String(),
    };
  }
}

const _officesSpec = _TableSpec(
  table: 'offices',
  primaryKey: 'office',
  sheetAliases: <String>['offices', 'office', 'τμηματα', 'γραφεια'],
  fallbackSheetIndex: 0,
  columns: <_ColumnSpec>[
    _ColumnSpec('office', aliases: <String>['κωδικος', 'γραφειο']),
    _ColumnSpec('office_name', aliases: <String>['ονομαγραφειου', 'περιγραφη']),
    _ColumnSpec('organization'),
    _ColumnSpec('organization_name'),
    _ColumnSpec('department'),
    _ColumnSpec('department_name'),
    _ColumnSpec('responsible'),
    _ColumnSpec('e_mail', aliases: <String>['email']),
    _ColumnSpec('phones', aliases: <String>['phone', 'telephone', 'τηλεφωνα']),
    _ColumnSpec('building'),
    _ColumnSpec('level'),
  ],
  alwaysOriginalTextColumns: <String, String>{
    'responsible': 'responsible_original_text',
  },
);

_TableSpec _ownersSpec(Set<int> officeIds) => _TableSpec(
  table: 'owners',
  primaryKey: 'owner',
  sheetAliases: <String>['owners', 'owner', 'υπαλληλοι', 'ιδιοκτητες'],
  fallbackSheetIndex: 1,
  columns: const <_ColumnSpec>[
    _ColumnSpec('owner', aliases: <String>['κωδικος']),
    _ColumnSpec('last_name', aliases: <String>['επωνυμο']),
    _ColumnSpec('first_name', aliases: <String>['ονομα']),
    _ColumnSpec('office'),
    _ColumnSpec('e_mail', aliases: <String>['email']),
    _ColumnSpec('phones', aliases: <String>['phone', 'telephone', 'τηλεφωνα']),
  ],
  foreignKeys: <_ForeignKeySpec>[
    _ForeignKeySpec(
      'office',
      officeIds,
      originalTextColumn: 'office_original_text',
    ),
  ],
);

const _modelSpec = _TableSpec(
  table: 'model',
  primaryKey: 'model',
  sheetAliases: <String>['model', 'models', 'μοντελα'],
  fallbackSheetIndex: 2,
  columns: <_ColumnSpec>[
    _ColumnSpec('model', aliases: <String>['κωδικος']),
    _ColumnSpec('model_name', aliases: <String>['μοντελο', 'ονομα']),
    _ColumnSpec('category_code'),
    _ColumnSpec('category_name'),
    _ColumnSpec('subcategory_code'),
    _ColumnSpec('subcategory_name'),
    _ColumnSpec('manufacturer'),
    _ColumnSpec('manufacturer_name'),
    _ColumnSpec('manufacturer_code'),
    _ColumnSpec('attributes'),
    _ColumnSpec('consumables'),
    _ColumnSpec('network_connectivity'),
  ],
  alwaysOriginalTextColumns: <String, String>{
    'category_code': 'category_code_original_text',
    'subcategory_code': 'subcategory_code_original_text',
    'manufacturer': 'manufacturer_original_text',
  },
);

const _contractsSpec = _TableSpec(
  table: 'contracts',
  primaryKey: 'contract',
  sheetAliases: <String>['contracts', 'contract', 'συμβασεις'],
  fallbackSheetIndex: 3,
  columns: <_ColumnSpec>[
    _ColumnSpec('contract', aliases: <String>['κωδικος']),
    _ColumnSpec('contract_name', aliases: <String>['συμβαση', 'ονομα']),
    _ColumnSpec('category'),
    _ColumnSpec('category_name'),
    _ColumnSpec('supplier'),
    _ColumnSpec('supplier_name'),
    _ColumnSpec('start_date', isDate: true),
    _ColumnSpec('end_date', isDate: true),
    _ColumnSpec('declaration'),
    _ColumnSpec('award'),
    _ColumnSpec('cost'),
    _ColumnSpec('committee'),
    _ColumnSpec('comments'),
  ],
  alwaysOriginalTextColumns: <String, String>{
    'category': 'category_original_text',
    'supplier': 'supplier_original_text',
  },
);

_TableSpec _equipmentSpec(
  Set<int> modelIds,
  Set<int> contractIds,
  Set<int> ownerIds,
  Set<int> officeIds,
) => _TableSpec(
  table: 'equipment',
  primaryKey: 'code',
  sheetAliases: const <String>['equipment', 'equipments', 'εξοπλισμος'],
  fallbackSheetIndex: 4,
  columns: const <_ColumnSpec>[
    _ColumnSpec('code', aliases: <String>['κωδικος']),
    _ColumnSpec('description', aliases: <String>['περιγραφη']),
    _ColumnSpec('model'),
    _ColumnSpec('serial_no', aliases: <String>['serial', 'serialnumber']),
    _ColumnSpec('asset_no', aliases: <String>['asset', 'assetnumber']),
    _ColumnSpec('state'),
    _ColumnSpec('state_name'),
    _ColumnSpec('set_master'),
    _ColumnSpec('contract'),
    _ColumnSpec('maintenance_contract'),
    _ColumnSpec('receiving_date', isDate: true),
    _ColumnSpec('end_of_guarantee_date', isDate: true),
    _ColumnSpec('cost'),
    _ColumnSpec('owner'),
    _ColumnSpec('office'),
    _ColumnSpec('attributes'),
    _ColumnSpec('comments'),
  ],
  foreignKeys: <_ForeignKeySpec>[
    _ForeignKeySpec(
      'model',
      modelIds,
      originalTextColumn: 'model_original_text',
    ),
    _ForeignKeySpec(
      'contract',
      contractIds,
      originalTextColumn: 'contract_original_text',
    ),
    _ForeignKeySpec(
      'owner',
      ownerIds,
      originalTextColumn: 'owner_original_text',
    ),
    _ForeignKeySpec(
      'office',
      officeIds,
      originalTextColumn: 'office_original_text',
    ),
  ],
  alwaysOriginalTextColumns: const <String, String>{
    'set_master': 'set_master_original_text',
    'state': 'state_original_text',
  },
);
