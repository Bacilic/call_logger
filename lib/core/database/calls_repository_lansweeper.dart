part of 'calls_repository.dart';

mixin CallsRepositoryLansweeperMixin on CallsRepositoryCore {
  /// Μέγιστο αριθμητικό Lansweeper ticket id από κλήσεις και ιστορικό links.
  Future<int?> maxNumericLansweeperTicketId() async {
    final rows = await db.rawQuery('''
      SELECT MAX(CAST(ticket_id AS INTEGER)) AS max_id
      FROM (
        SELECT trim(lansweeper_main_ticket_id) AS ticket_id
        FROM calls
        WHERE trim(lansweeper_main_ticket_id) != ''
          AND trim(lansweeper_main_ticket_id) GLOB '[0-9]*'
          AND (is_deleted IS NULL OR is_deleted = 0)
        UNION
        SELECT trim(external_id) AS ticket_id
        FROM call_external_links
        WHERE provider = 'lansweeper'
          AND trim(external_id) != ''
          AND trim(external_id) GLOB '[0-9]*'
      )
      ''');
    if (rows.isEmpty) return null;
    final value = rows.first['max_id'];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Πρόταση επόμενου ticket id (μέγιστο αριθμητικό + 1), ή null αν δεν υπάρχει.
  Future<String?> suggestedNextLansweeperTicketId() async {
    final maxId = await maxNumericLansweeperTicketId();
    if (maxId == null) return null;
    return '${maxId + 1}';
  }

  /// Πλήθος κλήσεων με το ίδιο Lansweeper ticket id (trimmed σύγκριση).
  Future<int> countCallsWithLansweeperTicketId(
    String ticketId, {
    int? excludeCallId,
    bool registeredOnly = false,
  }) async {
    final normalized = ticketId.trim();
    if (normalized.isEmpty) return 0;
    final clauses = <String>[
      "trim(lansweeper_main_ticket_id) = ?",
      '(is_deleted IS NULL OR is_deleted = 0)',
    ];
    final args = <Object?>[normalized];
    if (excludeCallId != null) {
      clauses.add('id != ?');
      args.add(excludeCallId);
    }
    if (registeredOnly) {
      clauses.add("lansweeper_state = 'sent'");
    }
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM calls WHERE ${clauses.join(' AND ')}',
      args,
    );
    if (rows.isEmpty) return 0;
    final value = rows.first['c'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Ενημερώνει την κατάσταση Lansweeper μιας κλήσης.
  Future<void> updateLansweeperState({
    required int callId,
    required String state,
    String? ticketId,
    bool updateTicketId = false,
    bool clearTicketId = false,
    String? syncedAt,
  }) async {
    final payload = <String, Object?>{
      'lansweeper_state': state,
      'lansweeper_last_sync_at': syncedAt ?? DateTime.now().toIso8601String(),
    };
    if (updateTicketId || clearTicketId) {
      payload['lansweeper_main_ticket_id'] = clearTicketId ? null : ticketId;
    }
    await db.update('calls', payload, where: 'id = ?', whereArgs: [callId]);
  }

  /// Ορίζει/ενημερώνει το κύριο ticket Lansweeper μιας κλήσης.
  Future<void> setLansweeperMainTicket({
    required int callId,
    required String? ticketId,
    String? syncedAt,
  }) async {
    await db.update(
      'calls',
      {
        'lansweeper_main_ticket_id': ticketId,
        'lansweeper_last_sync_at': syncedAt ?? DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [callId],
    );
  }

  /// Καταγράφει εξωτερικό link (π.χ. ticket id) για κλήση.
  Future<int> addExternalLink({
    required int callId,
    required String externalId,
    required String provider,
    String? createdAt,
    Map<String, dynamic>? metadata,
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? db;
    return e.insert('call_external_links', {
      'call_id': callId,
      'external_id': externalId,
      'provider': provider,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
      'metadata': metadata == null ? null : jsonEncode(metadata),
    });
  }

  /// Επιστρέφει το ιστορικό links εξωτερικών συστημάτων για μια κλήση.
  Future<List<Map<String, dynamic>>> getCallExternalLinks(
    int callId, {
    String? provider,
  }) async {
    final where = provider == null
        ? 'call_id = ?'
        : 'call_id = ? AND provider = ?';
    final args = provider == null
        ? <Object?>[callId]
        : <Object?>[callId, provider];
    final rows = await db.query(
      'call_external_links',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Χειροκίνητη σήμανση κλήσης ως περασμένη, με transactional write (state + link history).
  Future<void> markManualPassed({
    required int callId,
    required String ticketId,
    String? comment,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'calls',
        {
          'lansweeper_state': 'sent',
          'lansweeper_main_ticket_id': ticketId,
          'lansweeper_last_sync_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [callId],
      );
      await addExternalLink(
        callId: callId,
        externalId: ticketId,
        provider: 'lansweeper',
        createdAt: nowIso,
        metadata: <String, dynamic>{
          'mode': 'manual',
          if (comment != null && comment.trim().isNotEmpty)
            'comment': comment.trim(),
        },
        executor: txn,
      );
    });
  }

  /// Επιτυχής συγχρονισμός Lansweeper με transactional write (state + link history).
  Future<void> markLansweeperSynced({
    required int callId,
    required String ticketId,
    required String provider,
    Map<String, dynamic>? metadata,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'calls',
        {
          'lansweeper_state': 'sent',
          'lansweeper_main_ticket_id': ticketId,
          'lansweeper_last_sync_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [callId],
      );
      await addExternalLink(
        callId: callId,
        externalId: ticketId,
        provider: provider,
        createdAt: nowIso,
        metadata: metadata,
        executor: txn,
      );
    });
  }
}
