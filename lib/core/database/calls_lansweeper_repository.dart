import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'audit_service.dart';
import 'calls_audit_line.dart';
import 'calls_search_index.dart';

/// Πώς ονομάζεται στο Ιστορικό Εφαρμογής η αλλαγή κατάστασης Lansweeper.
///
/// Ξεχωριστή ενέργεια ανά γεγονός και όχι σκέτη «ΤΡΟΠΟΠΟΙΗΣΗ ΚΛΗΣΗΣ»: το
/// ερώτημα που κάνει κανείς είναι «πότε στάλθηκε αυτή η κλήση και ποιος την
/// έστειλε», και ως διακριτή ενέργεια φιλτράρεται στο Ιστορικό αντί να
/// θάβεται ανάμεσα στις καθημερινές επεξεργασίες.
String lansweeperAuditAction(String state) => switch (state.trim()) {
  'sent' => 'ΚΑΤΑΧΩΡΗΣΗ ΣΤΟ LANSWEEPER',
  'unsent' => 'ΑΠΟΣΥΡΣΗ ΑΠΟ LANSWEEPER',
  'excluded' => 'ΕΞΑΙΡΕΣΗ ΑΠΟ LANSWEEPER',
  'failed' => 'ΑΠΟΤΥΧΙΑ ΚΑΤΑΧΩΡΗΣΗΣ LANSWEEPER',
  _ => 'ΑΛΛΑΓΗ ΚΑΤΑΣΤΑΣΗΣ LANSWEEPER',
};

/// Κατάσταση Lansweeper κλήσεων + ιστορικό εξωτερικών links (tickets).
class CallsLansweeperRepository {
  const CallsLansweeperRepository(this.db);

  final Database db;

  /// Τα πεδία που αξίζουν καταγραφή. Το `lansweeper_last_sync_at` αλλάζει σε
  /// κάθε εγγραφή και θα γέμιζε το ιστορικό με θόρυβο.
  static const List<String> _auditedFields = [
    'lansweeper_state',
    'lansweeper_main_ticket_id',
  ];

  Future<Map<String, Object?>> _readAuditedFields(
    DatabaseExecutor e,
    int callId,
  ) async {
    final rows = await e.query(
      'calls',
      columns: _auditedFields,
      where: 'id = ?',
      whereArgs: [callId],
      limit: 1,
    );
    return rows.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.from(rows.first);
  }

  /// Γράφει την αλλαγή στα `calls` **και** την καταγράφει στο Ιστορικό.
  ///
  /// ΜΟΝΑΔΙΚΟ σημείο εγγραφής για τις τέσσερις ροές κατάστασης Lansweeper: αν
  /// κάποια έγραφε μόνη της, θα ξανάνοιγε η τρύπα που άφηνε κάθε καταχώρηση
  /// αόρατη στο Ιστορικό — η κλήση φαινόταν για πάντα «Μη αποσταλμένη».
  Future<void> _applyAndLog(
    DatabaseExecutor e, {
    required int callId,
    required Map<String, Object?> payload,
    required String action,
    Map<String, dynamic>? extraNewValues,
  }) async {
    final before = await _readAuditedFields(e, callId);
    await e.update('calls', payload, where: 'id = ?', whereArgs: [callId]);
    // Το ticket συμμετέχει στο ευρετήριο αναζήτησης: κάθε ροή που το αλλάζει
    // ξαναχτίζει το ευρετήριο στην ΙΔΙΑ συναλλαγή, αλλιώς η κλήση δεν βρίσκεται
    // από τον αριθμό της (ή βρίσκεται από ticket που δεν έχει πια).
    if (payload.containsKey('lansweeper_main_ticket_id')) {
      await CallsSearchIndex(db).rebuildSearchIndexForCallIdInTxn(e, callId);
    }
    final after = await _readAuditedFields(e, callId);

    final oldValues = <String, dynamic>{};
    final newValues = <String, dynamic>{};
    for (final field in _auditedFields) {
      final a = before[field];
      final b = after[field];
      if (a?.toString() != b?.toString()) {
        oldValues[field] = a;
        newValues[field] = b;
      }
    }
    if (extraNewValues != null) newValues.addAll(extraNewValues);
    // Καμία ουσιαστική αλλαγή (π.χ. επανακαταχώρηση στο ίδιο ticket): δεν
    // γεμίζουμε το ιστορικό με εγγραφές που δεν λένε τίποτα.
    if (newValues.isEmpty) return;

    final user = await AuditService.performingUser(e);
    final entityName = (await CallsAuditLine(
      db,
    ).buildCallAuditDisplayLine(callId, executor: e)).trim();
    await AuditService.log(
      e,
      action: action,
      userPerforming: user,
      details: 'calls id=$callId',
      entityType: AuditEntityTypes.call,
      entityId: callId,
      entityName: entityName.isEmpty ? null : entityName,
      oldValues: oldValues.isEmpty ? null : oldValues,
      newValues: newValues,
    );
  }

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
    await db.transaction(
      (txn) => _applyAndLog(
        txn,
        callId: callId,
        payload: payload,
        action: lansweeperAuditAction(state),
      ),
    );
  }

  /// Ορίζει/ενημερώνει το κύριο ticket Lansweeper μιας κλήσης.
  Future<void> setLansweeperMainTicket({
    required int callId,
    required String? ticketId,
    String? syncedAt,
  }) async {
    await db.transaction(
      (txn) => _applyAndLog(
        txn,
        callId: callId,
        payload: {
          'lansweeper_main_ticket_id': ticketId,
          'lansweeper_last_sync_at':
              syncedAt ?? DateTime.now().toIso8601String(),
        },
        action: 'ΑΛΛΑΓΗ TICKET LANSWEEPER',
      ),
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
    final trimmedComment = comment?.trim() ?? '';
    await db.transaction((txn) async {
      await _applyAndLog(
        txn,
        callId: callId,
        payload: {
          'lansweeper_state': 'sent',
          'lansweeper_main_ticket_id': ticketId,
          'lansweeper_last_sync_at': nowIso,
        },
        action: 'ΧΕΙΡΟΚΙΝΗΤΗ ΚΑΤΑΧΩΡΗΣΗ ΣΤΟ LANSWEEPER',
        extraNewValues: trimmedComment.isEmpty
            ? null
            : <String, dynamic>{'comment': trimmedComment},
      );
      await addExternalLink(
        callId: callId,
        externalId: ticketId,
        provider: 'lansweeper',
        createdAt: nowIso,
        metadata: <String, dynamic>{
          'mode': 'manual',
          if (trimmedComment.isNotEmpty) 'comment': trimmedComment,
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
      await _applyAndLog(
        txn,
        callId: callId,
        payload: {
          'lansweeper_state': 'sent',
          'lansweeper_main_ticket_id': ticketId,
          'lansweeper_last_sync_at': nowIso,
        },
        action: 'ΚΑΤΑΧΩΡΗΣΗ ΣΤΟ LANSWEEPER',
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
