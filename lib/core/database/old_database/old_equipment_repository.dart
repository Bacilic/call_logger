import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'lamp_database_provider.dart';

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

  Future<List<Map<String, Object?>>> searchByFields(
    String databasePath,
    OldEquipmentSearchFilters filters, {
    int limit = 100,
  }) async {
    final db = await _databaseProvider.open(databasePath);
    final where = <String>[];
    final args = <Object?>[];

    void addLike(String? value, List<String> columns) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) return;
      where.add('(${columns.map((c) => '$c LIKE ?').join(' OR ')})');
      args.addAll(List<Object?>.filled(columns.length, '%$trimmed%'));
    }

    addLike(filters.code, <String>['CAST(e.code AS TEXT)']);
    addLike(filters.description, <String>['e.description']);
    addLike(filters.serialNo, <String>['e.serial_no']);
    addLike(filters.assetNo, <String>['e.asset_no']);
    addLike(filters.model, <String>['m.model_name', 'e.model_original_text']);
    addLike(filters.contract, <String>[
      'c.contract_name',
      'e.contract_original_text',
      'c.supplier_name',
    ]);
    addLike(filters.state, <String>['e.state_name', 'e.state_original_text']);
    addLike(filters.owner, <String>[
      "COALESCE(o.last_name, '') || ' ' || COALESCE(o.first_name, '')",
      'e.owner_original_text',
      'o.phones',
      'o.e_mail',
    ]);
    addLike(filters.office, <String>[
      'f.office_name',
      'f.department_name',
      'e.office_original_text',
      'f.phones',
    ]);
    addLike(filters.phone, <String>['o.phones', 'f.phones']);

    return _search(
      db,
      whereClause: where.isEmpty ? null : where.join(' AND '),
      args: args,
      limit: limit,
    );
  }

  Future<List<Map<String, Object?>>> globalSearch(
    String databasePath,
    String query, {
    int limit = 100,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return <Map<String, Object?>>[];
    final db = await _databaseProvider.open(databasePath);
    final columns = _globalSearchColumns;
    final where = '(${columns.map((c) => '$c LIKE ?').join(' OR ')})';
    final args = List<Object?>.filled(columns.length, '%$trimmed%');
    return _search(db, whereClause: where, args: args, limit: limit);
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

  Future<List<Map<String, Object?>>> _search(
    Database db, {
    required String? whereClause,
    required List<Object?> args,
    required int limit,
  }) {
    return db.rawQuery(
      '''
      SELECT
        e.code,
        e.description,
        e.serial_no,
        e.asset_no,
        e.state_name,
        e.set_master,
        e.set_master_original_text,
        e.owner_original_text,
        e.office_original_text,
        e.model_original_text,
        e.contract_original_text,
        m.model_name,
        m.category_name,
        m.manufacturer_name,
        c.contract_name,
        c.supplier_name,
        o.owner,
        o.last_name,
        o.first_name,
        o.e_mail AS owner_email,
        o.phones AS owner_phones,
        f.office,
        f.office_name,
        f.department_name,
        f.phones AS office_phones,
        f.building,
        f.level
      FROM equipment e
      LEFT JOIN model m ON m.model = e.model
      LEFT JOIN contracts c ON c.contract = e.contract
      LEFT JOIN owners o ON o.owner = e.owner
      LEFT JOIN offices f ON f.office = e.office
      ${whereClause == null ? '' : 'WHERE $whereClause'}
      ORDER BY e.code
      LIMIT ?
      ''',
      <Object?>[...args, limit],
    );
  }

  static const List<String> _globalSearchColumns = <String>[
    'CAST(e.code AS TEXT)',
    'e.description',
    'e.serial_no',
    'e.asset_no',
    'e.state_name',
    'e.state_original_text',
    'e.owner_original_text',
    'e.office_original_text',
    'e.model_original_text',
    'e.contract_original_text',
    'e.set_master_original_text',
    'm.model_name',
    'm.category_name',
    'm.manufacturer_name',
    'c.contract_name',
    'c.supplier_name',
    "COALESCE(o.last_name, '') || ' ' || COALESCE(o.first_name, '')",
    'o.e_mail',
    'o.phones',
    'f.office_name',
    'f.department_name',
    'f.phones',
    'f.building',
  ];
}
