import '../../utils/search_text_normalizer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'lamp_database_provider.dart';

/// Αποτέλεσμα αναζήτησης: εμφανιζόμενες γραμμές + συνολικός αριθμός ταιριασμάτων.
class OldEquipmentSearchResult {
  const OldEquipmentSearchResult({
    required this.rows,
    required this.totalCount,
  });

  final List<Map<String, Object?>> rows;
  final int totalCount;
}

enum OldEquipmentSectionType {
  equipment,
  model,
  contract,
  owner,
  department,
}

class OldEquipmentUpdateResult {
  const OldEquipmentUpdateResult({
    required this.success,
    this.message,
  });

  final bool success;
  final String? message;
}

class OldEquipmentSearchFilters {
  const OldEquipmentSearchFilters({
    this.code,
    this.description,
    this.serialNo,
    this.assetNo,
    this.owner,
    this.office,
    this.phone,
    this.model,
    this.contract,
    this.state,
  });

  final String? code;
  final String? description;
  final String? serialNo;
  final String? assetNo;
  final String? owner;
  final String? office;
  final String? phone;
  final String? model;
  final String? contract;
  final String? state;
}

class OldEquipmentRepository {
  OldEquipmentRepository({LampDatabaseProvider? databaseProvider})
    : _databaseProvider = databaseProvider ?? LampDatabaseProvider.instance;

  final LampDatabaseProvider _databaseProvider;
  final Map<String, _SearchCacheEntry> _cacheByPath = <String, _SearchCacheEntry>{};

  /// Αύξηση όταν αλλάζει το SELECT / κανονικοποίηση ώστε να εκκαθαρίζεται η cache.
  static const int _searchCacheSchemaVersion = 3;

  static String _cacheKey(String databasePath) =>
      '${databasePath.trim()}#v$_searchCacheSchemaVersion';

  Future<void> preloadSearchCache(String databasePath) async {
    final path = databasePath.trim();
    if (path.isEmpty) return;
    final cache = await _buildCache(path);
    _cacheByPath[_cacheKey(path)] = cache;
  }

  Future<OldEquipmentSearchResult> searchByFields(
    String databasePath,
    OldEquipmentSearchFilters filters, {
    required int maxDisplay,
  }) async {
    final hasAnyField =
        _normalizeMaybe(filters.code) != null ||
        _normalizeMaybe(filters.description) != null ||
        _normalizeMaybe(filters.serialNo) != null ||
        _normalizeMaybe(filters.assetNo) != null ||
        _normalizeMaybe(filters.owner) != null ||
        _normalizeMaybe(filters.office) != null ||
        _normalizeMaybe(filters.phone) != null ||
        _normalizeMaybe(filters.model) != null ||
        _normalizeMaybe(filters.contract) != null ||
        _normalizeMaybe(filters.state) != null;
    if (!hasAnyField) {
      return const OldEquipmentSearchResult(rows: <Map<String, Object?>>[], totalCount: 0);
    }
    final cap = maxDisplay.clamp(1, 1000000);
    final cache = await _ensureCache(databasePath);
    var totalCount = 0;
    final displayed = <Map<String, Object?>>[];
    for (final row in cache.rows) {
      if (!_matchesFieldFilters(row, filters)) continue;
      totalCount++;
      if (displayed.length < cap) {
        displayed.add(row.dto);
      }
    }
    return OldEquipmentSearchResult(rows: displayed, totalCount: totalCount);
  }

  Future<OldEquipmentSearchResult> globalSearch(
    String databasePath,
    String query, {
    required int maxDisplay,
  }) async {
    final normalizedQuery = _normalizeMaybe(query);
    if (normalizedQuery == null) {
      return const OldEquipmentSearchResult(rows: <Map<String, Object?>>[], totalCount: 0);
    }
    final cap = maxDisplay.clamp(1, 1000000);
    final cache = await _ensureCache(databasePath);
    var totalCount = 0;
    final displayed = <Map<String, Object?>>[];
    for (final row in cache.rows) {
      if (!_containsAllTokens(row.normalizedText, normalizedQuery)) continue;
      totalCount++;
      if (displayed.length < cap) {
        displayed.add(row.dto);
      }
    }
    return OldEquipmentSearchResult(rows: displayed, totalCount: totalCount);
  }

  Future<List<Map<String, Object?>>> relatedEquipment(
    String databasePath,
    int code,
  ) async {
    final db = await _databaseProvider.open(databasePath);
    return db.rawQuery(
      '''
      SELECT code, description, serial_no, asset_no, state_name
      FROM equipment
      WHERE set_master = ? OR code = (
        SELECT set_master FROM equipment WHERE code = ?
      )
      ORDER BY code
      ''',
      <Object?>[code, code],
    );
  }

  Future<OldEquipmentUpdateResult> updateSection({
    required String databasePath,
    required int id,
    required OldEquipmentSectionType sectionType,
    required Map<String, Object?> updatedFields,
  }) async {
    final spec = _UpdateSectionSpec.forType(sectionType);
    final dbFields = <String, Object?>{};
    for (final entry in updatedFields.entries) {
      final column = spec.allowedColumnsByField[entry.key];
      if (column != null) {
        dbFields[column] = entry.value;
      }
    }
    if (dbFields.isEmpty) {
      return const OldEquipmentUpdateResult(
        success: false,
        message: 'Δεν υπάρχουν επιτρεπόμενα πεδία για αποθήκευση.',
      );
    }

    final path = databasePath.trim();
    try {
      final db = await _databaseProvider.open(path, mode: LampDatabaseMode.write);
      final updatedCount = await db.transaction<int>((txn) async {
        return txn.update(
          spec.table,
          dbFields,
          where: '${spec.idColumn} = ?',
          whereArgs: <Object?>[id],
        );
      });
      if (updatedCount == 0) {
        return const OldEquipmentUpdateResult(
          success: false,
          message: 'Δεν βρέθηκε εγγραφή για ενημέρωση.',
        );
      }
      _cacheByPath.remove(_cacheKey(path));
      return const OldEquipmentUpdateResult(success: true);
    } catch (e) {
      return OldEquipmentUpdateResult(
        success: false,
        message: 'Η αποθήκευση απέτυχε: $e',
      );
    }
  }

  Future<List<Map<String, Object?>>> dataIssues(
    String databasePath, {
    int limit = 500,
  }) async {
    final db = await _databaseProvider.open(databasePath);
    return db.query('data_issues', orderBy: 'id DESC', limit: limit);
  }

  Future<int> dataIssueCount(String databasePath) async {
    final db = await _databaseProvider.open(databasePath);
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM data_issues');
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<_SearchCacheEntry> _ensureCache(String databasePath) async {
    final path = databasePath.trim();
    final key = _cacheKey(path);
    final existing = _cacheByPath[key];
    if (existing != null) return existing;
    final cache = await _buildCache(path);
    _cacheByPath[key] = cache;
    return cache;
  }

  Future<_SearchCacheEntry> _buildCache(String databasePath) async {
    await _ensureSearchIndexTable(databasePath);
    await _rebuildSearchIndex(databasePath);
    final db = await _databaseProvider.open(databasePath);
    final rows = await _loadSourceRows(db);
    final indexedRows = rows.map(_mapToIndexedRow).toList(growable: false);
    return _SearchCacheEntry(rows: indexedRows);
  }

  Future<void> _ensureSearchIndexTable(String databasePath) async {
    try {
      final db = await _databaseProvider.open(
        databasePath,
        mode: LampDatabaseMode.write,
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS search_index (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_table TEXT NOT NULL,
          source_id INTEGER NOT NULL,
          normalized_text TEXT NOT NULL,
          UNIQUE(source_table, source_id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_search_index_source ON search_index(source_table, source_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_search_index_normalized ON search_index(normalized_text)',
      );
    } catch (_) {
      // Αν η βάση είναι μόνο-ανάγνωση, συνεχίζουμε με in-memory cache χωρίς persisted index.
    }
  }

  Future<void> _rebuildSearchIndex(String databasePath) async {
    try {
      final db = await _databaseProvider.open(
        databasePath,
        mode: LampDatabaseMode.write,
      );
      final rows = await _loadSourceRows(db);
      await db.transaction((txn) async {
        await txn.delete('search_index', where: 'source_table = ?', whereArgs: <Object?>['equipment']);
        final batch = txn.batch();
        for (final row in rows) {
          final sourceId = _toInt(row['_source_id']) ?? 0;
          final normalizedText = _buildNormalizedSearchText(row);
          batch.insert('search_index', <String, Object?>{
            'source_table': 'equipment',
            'source_id': sourceId,
            'normalized_text': normalizedText,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {
      // persisted search_index είναι βελτιστοποίηση. Η κύρια λειτουργία
      // συνεχίζει μέσω in-memory κανονικοποιημένου cache.
    }
  }

  Future<List<Map<String, Object?>>> _loadSourceRows(Database db) {
    return db.rawQuery(
      '''
      SELECT
        e.rowid AS _source_id,
        e.code,
        e.description,
        e.serial_no,
        e.asset_no,
        e.state_name,
        e.state_original_text,
        e.set_master,
        e.set_master_original_text,
        e.owner_original_text,
        e.office_original_text,
        e.model_original_text,
        e.contract_original_text,
        e.model AS model_id,
        e.contract AS contract_id,
        e.owner AS owner_id,
        e.office AS office_id,
        e.maintenance_contract,
        e.receiving_date,
        e.end_of_guarantee_date,
        e.cost,
        e.attributes AS equipment_attributes,
        e.comments AS equipment_comments,
        m.model_name,
        m.category_name,
        m.subcategory_name,
        m.manufacturer_name,
        m.attributes AS model_attributes,
        m.consumables,
        c.contract_name,
        c.supplier_name,
        c.category_name AS contract_category_name,
        c.comments AS contract_comments,
        c.award AS contract_award,
        c.declaration AS contract_declaration,
        o.owner,
        o.last_name,
        o.first_name,
        o.e_mail AS owner_email,
        o.phones AS owner_phones,
        f.office,
        f.office_name,
        f.organization_name,
        f.e_mail AS office_email,
        f.department_name,
        f.phones AS office_phones,
        f.building,
        f.level
      FROM equipment e
      LEFT JOIN model m ON m.model = e.model
      LEFT JOIN contracts c ON c.contract = e.contract
      LEFT JOIN owners o ON o.owner = e.owner
      LEFT JOIN offices f ON f.office = e.office
      ORDER BY e.code
      ''',
    );
  }

  _IndexedEquipmentRow _mapToIndexedRow(Map<String, Object?> row) {
    final dto = Map<String, Object?>.from(row)..remove('_source_id');
    return _IndexedEquipmentRow(
      sourceId: _toInt(row['_source_id']) ?? 0,
      normalizedText: _buildNormalizedSearchText(row),
      dto: dto,
    );
  }

  String _buildNormalizedSearchText(Map<String, Object?> row) {
    final parts = <String>[
      _toText(row['code']),
      _toText(row['description']),
      _toText(row['serial_no']),
      _toText(row['asset_no']),
      _toText(row['state_name']),
      _toText(row['state_original_text']),
      _toText(row['set_master_original_text']),
      _toText(row['owner_original_text']),
      _toText(row['office_original_text']),
      _toText(row['model_original_text']),
      _toText(row['contract_original_text']),
      _toText(row['model_id']),
      _toText(row['contract_id']),
      _toText(row['owner_id']),
      _toText(row['office_id']),
      _toText(row['maintenance_contract']),
      _toText(row['receiving_date']),
      _toText(row['end_of_guarantee_date']),
      _toText(row['cost']),
      _toText(row['equipment_attributes']),
      _toText(row['equipment_comments']),
      _toText(row['model_name']),
      _toText(row['category_name']),
      _toText(row['subcategory_name']),
      _toText(row['manufacturer_name']),
      _toText(row['model_attributes']),
      _toText(row['consumables']),
      _toText(row['contract_name']),
      _toText(row['supplier_name']),
      _toText(row['contract_category_name']),
      _toText(row['contract_comments']),
      _toText(row['contract_award']),
      _toText(row['contract_declaration']),
      _toText(row['last_name']),
      _toText(row['first_name']),
      _toText(row['owner_email']),
      _toText(row['owner_phones']),
      _toText(row['office_name']),
      _toText(row['organization_name']),
      _toText(row['office_email']),
      _toText(row['department_name']),
      _toText(row['office_phones']),
      _toText(row['building']),
      _toText(row['level']),
    ];
    return SearchTextNormalizer.normalizeForSearch(parts.join(' '));
  }

  bool _matchesFieldFilters(
    _IndexedEquipmentRow row,
    OldEquipmentSearchFilters filters,
  ) {
    final dto = row.dto;
    return _matchesField(_fieldTextForCode(dto), filters.code) &&
        _matchesField(_fieldTextForDescription(dto), filters.description) &&
        _matchesField(_fieldTextForSerialNo(dto), filters.serialNo) &&
        _matchesField(_fieldTextForAssetNo(dto), filters.assetNo) &&
        _matchesField(_fieldTextForOwner(dto), filters.owner) &&
        _matchesField(_fieldTextForOffice(dto), filters.office) &&
        _matchesField(_fieldTextForPhone(dto), filters.phone) &&
        _matchesField(_fieldTextForModel(dto), filters.model) &&
        _matchesField(_fieldTextForContract(dto), filters.contract) &&
        _matchesField(_fieldTextForState(dto), filters.state);
  }

  bool _matchesField(String fieldText, String? queryRaw) {
    final q = _normalizeMaybe(queryRaw);
    if (q == null) return true;
    return _containsAllTokens(SearchTextNormalizer.normalizeForSearch(fieldText), q);
  }

  String _fieldTextForCode(Map<String, Object?> row) => _toText(row['code']);
  String _fieldTextForDescription(Map<String, Object?> row) =>
      '${_toText(row['description'])} ${_toText(row['equipment_attributes'])} ${_toText(row['equipment_comments'])}';
  String _fieldTextForSerialNo(Map<String, Object?> row) => _toText(row['serial_no']);
  String _fieldTextForAssetNo(Map<String, Object?> row) => _toText(row['asset_no']);
  String _fieldTextForState(Map<String, Object?> row) =>
      '${_toText(row['state_name'])} ${_toText(row['state_original_text'])}';
  String _fieldTextForModel(Map<String, Object?> row) =>
      '${_toText(row['model_name'])} ${_toText(row['model_original_text'])} '
      '${_toText(row['category_name'])} ${_toText(row['subcategory_name'])} '
      '${_toText(row['manufacturer_name'])} ${_toText(row['consumables'])}';
  String _fieldTextForContract(Map<String, Object?> row) =>
      '${_toText(row['contract_name'])} ${_toText(row['contract_original_text'])} '
      '${_toText(row['supplier_name'])} ${_toText(row['contract_category_name'])} '
      '${_toText(row['contract_comments'])} ${_toText(row['contract_award'])} '
      '${_toText(row['contract_declaration'])}';
  String _fieldTextForOwner(Map<String, Object?> row) =>
      '${_toText(row['last_name'])} ${_toText(row['first_name'])} ${_toText(row['owner_original_text'])} ${_toText(row['owner_phones'])} ${_toText(row['owner_email'])}';
  String _fieldTextForOffice(Map<String, Object?> row) =>
      '${_toText(row['office_name'])} ${_toText(row['organization_name'])} '
      '${_toText(row['office_email'])} ${_toText(row['department_name'])} '
      '${_toText(row['office_original_text'])} ${_toText(row['office_phones'])}';
  String _fieldTextForPhone(Map<String, Object?> row) =>
      '${_toText(row['owner_phones'])} ${_toText(row['office_phones'])}';

  bool _containsAllTokens(String normalizedText, String normalizedQuery) {
    final tokens = normalizedQuery.split(' ').where((t) => t.isNotEmpty);
    for (final token in tokens) {
      if (!normalizedText.contains(token)) return false;
    }
    return true;
  }

  String? _normalizeMaybe(String? value) {
    final t = value?.trim() ?? '';
    if (t.isEmpty) return null;
    final n = SearchTextNormalizer.normalizeForSearch(t);
    return n.isEmpty ? null : n;
  }

  String _toText(Object? value) => value?.toString() ?? '';
  int? _toInt(Object? value) => value is int ? value : int.tryParse(value?.toString() ?? '');
}

class _SearchCacheEntry {
  _SearchCacheEntry({required this.rows});
  final List<_IndexedEquipmentRow> rows;
}

class _IndexedEquipmentRow {
  _IndexedEquipmentRow({
    required this.sourceId,
    required this.normalizedText,
    required this.dto,
  });

  final int sourceId;
  final String normalizedText;
  final Map<String, Object?> dto;
}

class _UpdateSectionSpec {
  const _UpdateSectionSpec({
    required this.table,
    required this.idColumn,
    required this.allowedColumnsByField,
  });

  final String table;
  final String idColumn;
  final Map<String, String> allowedColumnsByField;

  static _UpdateSectionSpec forType(OldEquipmentSectionType type) {
    return switch (type) {
      OldEquipmentSectionType.equipment => const _UpdateSectionSpec(
        table: 'equipment',
        idColumn: 'code',
        allowedColumnsByField: <String, String>{
          'description': 'description',
          'serial_no': 'serial_no',
          'asset_no': 'asset_no',
          'set_master': 'set_master',
          'receiving_date': 'receiving_date',
          'end_of_guarantee_date': 'end_of_guarantee_date',
          'cost': 'cost',
          'equipment_comments': 'comments',
        },
      ),
      OldEquipmentSectionType.model => const _UpdateSectionSpec(
        table: 'model',
        idColumn: 'model',
        allowedColumnsByField: <String, String>{
          'model_name': 'model_name',
          'category_name': 'category_name',
          'subcategory_name': 'subcategory_name',
          'manufacturer_name': 'manufacturer_name',
          'model_attributes': 'attributes',
          'consumables': 'consumables',
        },
      ),
      OldEquipmentSectionType.contract => const _UpdateSectionSpec(
        table: 'contracts',
        idColumn: 'contract',
        allowedColumnsByField: <String, String>{
          'contract_name': 'contract_name',
          'contract_category_name': 'category_name',
          'supplier_name': 'supplier_name',
          'contract_award': 'award',
          'contract_declaration': 'declaration',
          'contract_comments': 'comments',
        },
      ),
      OldEquipmentSectionType.owner => const _UpdateSectionSpec(
        table: 'owners',
        idColumn: 'owner',
        allowedColumnsByField: <String, String>{
          'last_name': 'last_name',
          'first_name': 'first_name',
          'owner_email': 'e_mail',
          'owner_phones': 'phones',
        },
      ),
      OldEquipmentSectionType.department => const _UpdateSectionSpec(
        table: 'offices',
        idColumn: 'office',
        allowedColumnsByField: <String, String>{
          'office_name': 'office_name',
          'organization_name': 'organization_name',
          'department_name': 'department_name',
          'office_email': 'e_mail',
          'office_phones': 'phones',
          'building': 'building',
          'level': 'level',
        },
      ),
    };
  }
}
