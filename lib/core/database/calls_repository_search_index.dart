part of 'calls_repository.dart';

mixin CallsRepositorySearchIndexMixin on CallsRepositoryCore {
  /// Συγκεντρώνει κείμενα κλήσης + συσχετισμένου χρήστη/εξοπλισμού για `search_index` (σχήμα v1).
  Future<String> _buildCallSearchIndex(
    DatabaseExecutor executor,
    Map<String, dynamic> callMap,
  ) async {
    void addNonEmpty(List<String> parts, dynamic v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isNotEmpty) parts.add(s);
    }

    final parts = <String>[];

    addNonEmpty(parts, callMap['issue']);
    addNonEmpty(parts, callMap['category_text']);
    addNonEmpty(parts, callMap['caller_text']);
    addNonEmpty(parts, callMap['phone_text']);
    addNonEmpty(parts, callMap['department_text']);
    addNonEmpty(parts, callMap['equipment_text']);

    final callerId = callMap['caller_id'] as int?;
    if (callerId != null) {
      final userRows = await executor.rawQuery(
        '''
        SELECT u.first_name, u.last_name, d.name AS department_name
        FROM users u
        LEFT JOIN departments d ON u.department_id = d.id
        WHERE u.id = ?
        LIMIT 1
        ''',
        [callerId],
      );
      if (userRows.isNotEmpty) {
        final u = userRows.first;
        addNonEmpty(parts, u['first_name']);
        addNonEmpty(parts, u['last_name']);
        addNonEmpty(parts, u['department_name']);
      }
      final phoneRows = await executor.rawQuery(
        '''
        SELECT p.number FROM user_phones up
        JOIN phones p ON p.id = up.phone_id
        WHERE up.user_id = ?
        ORDER BY p.number
        ''',
        [callerId],
      );
      for (final pr in phoneRows) {
        addNonEmpty(parts, pr['number']);
      }
    }

    final equipmentId = callMap['equipment_id'] as int?;
    if (equipmentId != null) {
      final eqRows = await executor.query(
        'equipment',
        columns: ['code_equipment'],
        where: 'id = ?',
        whereArgs: [equipmentId],
        limit: 1,
      );
      if (eqRows.isNotEmpty) {
        addNonEmpty(parts, eqRows.first['code_equipment']);
      }
    }

    return SearchTextNormalizer.normalizeForSearch(parts.join(' '));
  }
  Future<void> _rebuildSearchIndexForCallRows(
    DatabaseExecutor executor,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row);
      final si = await _buildCallSearchIndex(executor, map);
      await executor.update(
        'calls',
        {'search_index': si},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  /// Επαναδόμηση `search_index` για μία κλήση βάσει id (integrity fix).
  Future<void> rebuildSearchIndexForCallId(int callId) async {
    await db.transaction((txn) async {
      await rebuildSearchIndexForCallIdInTxn(txn, callId);
    });
  }

  /// Επαναδόμηση `search_index` για μία κλήση μέσα σε transaction.
  Future<void> rebuildSearchIndexForCallIdInTxn(
    DatabaseExecutor executor,
    int callId,
  ) async {
    final rows = await executor.query(
      'calls',
      where: 'id = ?',
      whereArgs: [callId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await _rebuildSearchIndexForCallRows(executor, rows);
  }

  /// Επαναδόμηση `search_index` για όλες τις κλήσεις με [categoryId] (ίδιο [DatabaseExecutor] / transaction).
  Future<void> rebuildSearchIndexForCallsByCategoryId(
    DatabaseExecutor executor,
    int categoryId,
  ) async {
    final rows = await executor.query(
      'calls',
      where: 'category_id = ?',
      whereArgs: [categoryId],
    );
    await _rebuildSearchIndexForCallRows(executor, rows);
  }

  /// Επαναδόμηση `search_index` για μη-διαγραμμένες κλήσεις με [callerId].
  Future<void> rebuildSearchIndexForCallsByCallerId(
    DatabaseExecutor executor,
    int callerId,
  ) async {
    final rows = await executor.query(
      'calls',
      where: 'caller_id = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [callerId],
    );
    await _rebuildSearchIndexForCallRows(executor, rows);
  }

  /// Επαναδόμηση `search_index` για μη-διαγραμμένες κλήσεις με [equipmentId].
  Future<void> rebuildSearchIndexForCallsByEquipmentId(
    DatabaseExecutor executor,
    int equipmentId,
  ) async {
    final rows = await executor.query(
      'calls',
      where: 'equipment_id = ? AND COALESCE(is_deleted, 0) = 0',
      whereArgs: [equipmentId],
    );
    await _rebuildSearchIndexForCallRows(executor, rows);
  }
}
