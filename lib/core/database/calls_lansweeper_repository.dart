import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/history/services/lansweeper_registration_conflict.dart';
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

  /// Τα πεδία του καθαρού κειμένου που αξίζουν καταγραφή. Τα `refined_source` /
  /// `refined_at` μένουν έξω για τον ίδιο λόγο με το `lansweeper_last_sync_at`:
  /// αλλάζουν σε κάθε αποστολή και θα έπνιγαν το Ιστορικό σε θόρυβο.
  static const List<String> _refinedAuditedFields = ['issue', 'solution'];

  Future<Map<String, Object?>> _readFields(
    DatabaseExecutor e,
    int callId,
    List<String> fields,
  ) async {
    final rows = await e.query(
      'calls',
      columns: fields,
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
  /// Μία διαδρομή για κάθε εγγραφή κλήσης αυτού του repository: διάβασε το
  /// «πριν», γράψε, ξαναχτίσε το ευρετήριο όπου χρειάζεται, διάβασε το «μετά»,
  /// κατέγραψε μόνο ό,τι όντως άλλαξε. Οι δύο καλούντες διαφέρουν μόνο σε ποια
  /// πεδία παρακολουθούν και πώς ονομάζουν την ενέργεια.
  ///
  /// Το [guard] κρίνει το «πριν» **προτού** γραφτεί οτιδήποτε, μέσα στην ίδια
  /// συναλλαγή: εκεί ο έλεγχος είναι ατομικός (δεν υπάρχει παράθυρο ανάμεσα
  /// στην ανάγνωση και στην εγγραφή) και δωρεάν (η γραμμή διαβάζεται έτσι κι
  /// αλλιώς για το Ιστορικό). Πετώντας, ακυρώνει ολόκληρη τη συναλλαγή.
  /// Επιστρέφει `true` όταν η εγγραφή **άλλαξε** κάτι ουσιαστικό.
  ///
  /// Ο καλών το χρειάζεται: ό,τι συνοδεύει την αλλαγή (π.χ. εγγραφή στο
  /// ιστορικό συνδέσμων) δεν έχει λόγο να γραφτεί όταν τίποτα δεν κουνήθηκε.
  Future<bool> _updateAndLog(
    DatabaseExecutor e, {
    required int callId,
    required Map<String, Object?> payload,
    required List<String> auditedFields,
    required String action,
    required bool rebuildSearchIndex,
    Map<String, dynamic>? extraNewValues,
    void Function(Map<String, Object?> before)? guard,
  }) async {
    final before = await _readFields(e, callId, auditedFields);
    // Κλήση που δεν υπάρχει (π.χ. διαγράφηκε στο μεταξύ): καμία εγγραφή,
    // καμία εγγραφή ιστορικού για οντότητα-φάντασμα.
    if (before.isEmpty) return false;
    guard?.call(before);

    await e.update('calls', payload, where: 'id = ?', whereArgs: [callId]);
    if (rebuildSearchIndex) {
      await CallsSearchIndex(db).rebuildSearchIndexForCallIdInTxn(e, callId);
    }
    final after = await _readFields(e, callId, auditedFields);

    final oldValues = <String, dynamic>{};
    final newValues = <String, dynamic>{};
    for (final field in auditedFields) {
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
    if (newValues.isEmpty) return false;

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
    return true;
  }

  /// Αλλαγή κατάστασης/ticket Lansweeper.
  ///
  /// ΜΟΝΑΔΙΚΟ σημείο εγγραφής για τις τέσσερις ροές κατάστασης: αν κάποια
  /// έγραφε μόνη της, θα ξανάνοιγε η τρύπα που άφηνε κάθε καταχώρηση αόρατη
  /// στο Ιστορικό — η κλήση φαινόταν για πάντα «Μη αποσταλμένη».
  ///
  /// Είναι ΚΑΙ το μοναδικό σημείο επιβολής του φρουρού: το [expected] είναι η
  /// κατάσταση **όπως τη διάβασε η οθόνη**, και χωρίς αυτό μια σήμανση πάνω σε
  /// μπαγιάτικη ουρά αντικαθιστά το αίτημα που μόλις καταχώρησε ο συνάδελφος.
  /// Δεκτικό `null` μόνο ρητά — άγνοια της αφετηρίας σημαίνει «πέρνα» (μια
  /// εγγραφή από παλαιότερη έκδοση δεν γίνεται άσωστη), όχι «μπλόκαρε».
  Future<bool> _applyAndLog(
    DatabaseExecutor e, {
    required int callId,
    required Map<String, Object?> payload,
    required String action,
    required LansweeperRegistrationBaseline? expected,
    bool force = false,
    Map<String, dynamic>? extraNewValues,
  }) => _updateAndLog(
    e,
    callId: callId,
    payload: payload,
    auditedFields: _auditedFields,
    action: action,
    // Το ticket συμμετέχει στο ευρετήριο αναζήτησης: κάθε ροή που το αλλάζει
    // ξαναχτίζει το ευρετήριο στην ΙΔΙΑ συναλλαγή, αλλιώς η κλήση δεν βρίσκεται
    // από τον αριθμό της (ή βρίσκεται από ticket που δεν έχει πια).
    rebuildSearchIndex: payload.containsKey('lansweeper_main_ticket_id'),
    extraNewValues: extraNewValues,
    guard: (expected == null || force)
        ? null
        : (before) {
            final conflict = _conflictAgainst(
              before: before,
              expected: expected,
              payload: payload,
            );
            if (conflict != null) {
              throw LansweeperRegistrationStaleException(conflict);
            }
          },
  );

  /// Η διένεξη ανάμεσα στην αφετηρία της οθόνης και στη γραμμή όπως τη βρήκε η
  /// συναλλαγή· `null` όταν δεν υπάρχει λόγος να σταματήσει η εγγραφή.
  ///
  /// Η «πρόθεσή» μου δεν διαβάζεται από τον καλούντα αλλά από το ίδιο το
  /// payload: έτσι κάθε νέα ροή κατάστασης κρίνεται σωστά χωρίς να θυμηθεί
  /// κανείς να περιγράψει τι πάει να γράψει.
  static LansweeperRegistrationConflict? _conflictAgainst({
    required Map<String, Object?> before,
    required LansweeperRegistrationBaseline expected,
    required Map<String, Object?> payload,
  }) {
    final fresh = LansweeperRegistrationBaseline(
      state: before['lansweeper_state'] as String?,
      ticketId: before['lansweeper_main_ticket_id'] as String?,
    );
    final touchesTicketId = payload.containsKey('lansweeper_main_ticket_id');
    final conflict = LansweeperRegistrationConflict(
      expected: expected,
      fresh: fresh,
      attempted: LansweeperRegistrationAttempt(
        // Πεδίο που το payload δεν αγγίζει μένει όπως το βρίσκει: αλλιώς μια
        // εγγραφή μόνο-ticket θα φαινόταν να επαναφέρει και την κατάσταση.
        state: payload.containsKey('lansweeper_state')
            ? '${payload['lansweeper_state'] ?? ''}'
            : fresh.normalizedState,
        touchesTicketId: touchesTicketId,
        ticketId: touchesTicketId
            ? payload['lansweeper_main_ticket_id'] as String?
            : null,
      ),
    );
    return conflict.isConflict ? conflict : null;
  }

  /// Γράφει πίσω στις κλήσεις το εξευγενισμένο κείμενο της φόρμας Lansweeper.
  ///
  /// ΜΟΝΑΔΙΚΟ σημείο εγγραφής για κάθε έξοδο κειμένου προς το Lansweeper —
  /// υποβολή API, επανυποβολή, «Αντιγραφή & Άνοιγμα». Χωρίς αυτό το κείμενο
  /// έφευγε στο ticket (ή στο πρόχειρο) και η δουλειά του καθαρισμού χανόταν:
  /// η κλήση έμενε για πάντα με τη μία τηλεγραφική γραμμή που γράφτηκε βιαστικά
  /// στο τηλέφωνο, και η λύση δεν υπήρχε πουθενά στην εφαρμογή.
  ///
  /// Το καθαρό κείμενο ΑΝΤΙΚΑΘΙΣΤΑ την Περιγραφή (`issue`): από την v43 κάθε
  /// κλήση έχει ένα και μόνο κείμενο — το καλύτερο διαθέσιμο. Το πρόχειρο του
  /// τηλεφώνου χάνεται οριστικά με ρητή απόφαση (10/08/2026): το γράφει μόνο ο
  /// χρήστης, δυσλεξικά, και μετά τον εξευγενισμό δεν έχει αξία για κανέναν.
  /// Τα `refined_source`/`refined_at` κρατούν το ίχνος του πώς και πότε.
  ///
  /// Όλες οι [callIds] παίρνουν το ίδιο κείμενο. Όταν πολλές κλήσεις μπαίνουν
  /// σε ένα ticket, το κείμενο γράφτηκε για όλες μαζί — αφήνοντας τις υπόλοιπες
  /// κενές, θα έμεναν μόνιμα τηλεγραφικές χωρίς λόγο.
  /// Θα άλλαζε πράγματι κάτι η [saveRefinedTexts] με αυτά τα κείμενα;
  ///
  /// Ζει **δίπλα στην εγγραφή και τηρεί τους ίδιους κανόνες** — κενό πεδίο δεν
  /// αγγίζει ό,τι υπάρχει, και δύο κενά πεδία δεν γράφουν τίποτα. Αν η απάντηση
  /// εδώ αποκλίνει από τη συμπεριφορά της εγγραφής, το κουμπί που τη ρωτά θα
  /// λέει ψέματα: είτε θα δηλώνει «αποθηκεύτηκε» χωρίς να αλλάξει τίποτα, είτε
  /// θα μένει ανενεργό ενώ υπάρχει δουλειά να σωθεί.
  static bool wouldChangeTexts({
    required String problem,
    required String solution,
    required String? currentIssue,
    required String? currentSolution,
  }) {
    final trimmedProblem = problem.trim();
    final trimmedSolution = solution.trim();
    if (trimmedProblem.isEmpty && trimmedSolution.isEmpty) return false;
    if (trimmedProblem.isNotEmpty &&
        trimmedProblem != (currentIssue ?? '').trim()) {
      return true;
    }
    if (trimmedSolution.isNotEmpty &&
        trimmedSolution != (currentSolution ?? '').trim()) {
      return true;
    }
    return false;
  }

  Future<void> saveRefinedTexts({
    required List<int> callIds,
    required String problem,
    required String solution,
    required String source,
    String? refinedAt,
  }) async {
    final trimmedProblem = problem.trim();
    final trimmedSolution = solution.trim();
    // Άδεια φόρμα δεν σβήνει ό,τι έγραψε προηγούμενη αποστολή — και άδειο
    // επιμέρους πεδίο δεν αδειάζει ποτέ την Περιγραφή ή τη λύση της κλήσης.
    if (trimmedProblem.isEmpty && trimmedSolution.isEmpty) return;

    final ids = callIds.toSet().toList()..sort();
    if (ids.isEmpty) return;

    final payload = <String, Object?>{
      if (trimmedProblem.isNotEmpty) 'issue': trimmedProblem,
      if (trimmedSolution.isNotEmpty) 'solution': trimmedSolution,
      'refined_source': source,
      'refined_at': refinedAt ?? DateTime.now().toIso8601String(),
    };

    await db.transaction((txn) async {
      for (final callId in ids) {
        await _updateAndLog(
          txn,
          callId: callId,
          payload: payload,
          auditedFields: _refinedAuditedFields,
          action: 'ΚΑΘΑΡΟ ΚΕΙΜΕΝΟ ΚΛΗΣΗΣ',
          // Το καθαρό κείμενο συμμετέχει στην αναζήτηση: χωρίς το ξαναχτίσιμο,
          // η λέξη υπάρχει στη βάση αλλά δεν βρίσκει την κλήση.
          rebuildSearchIndex: true,
        );
      }
    });
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
  ///
  /// Πετά [LansweeperRegistrationStaleException] **πριν** γράψει οτιδήποτε,
  /// όταν κάποιος άλλος κούνησε την κλήση μετά την ανάγνωση του [expected].
  Future<void> updateLansweeperState({
    required int callId,
    required String state,
    required LansweeperRegistrationBaseline? expected,
    String? ticketId,
    bool updateTicketId = false,
    bool clearTicketId = false,
    bool force = false,
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
        expected: expected,
        force: force,
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
        // Καμία οθόνη δεν καλεί αυτή τη διαδρομή σήμερα, οπότε δεν υπάρχει
        // αφετηρία να δοθεί. Όποιος τη συνδέσει με ενέργεια χρήστη οφείλει να
        // περάσει το `expected` — αλλιώς η σήμανση θα γράφει στα τυφλά.
        expected: null,
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
  ///
  /// Το [expected] είναι η κατάσταση **όπως τη δείχνει η ουρά μου**. Στη
  /// ρουτίνα των 13:00 δύο άνθρωποι περνούν την ίδια λίστα: χωρίς αφετηρία, ο
  /// δεύτερος γράφει τον δικό του αριθμό πάνω στου πρώτου και το αίτημα εκείνου
  /// μένει ορφανό στο Lansweeper — σύστημα που η εφαρμογή δεν καθαρίζει.
  ///
  /// Πετά [LansweeperRegistrationStaleException] **πριν** γράψει οτιδήποτε.
  Future<void> markManualPassed({
    required int callId,
    required String ticketId,
    required LansweeperRegistrationBaseline? expected,
    bool force = false,
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
        expected: expected,
        force: force,
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
      final changed = await _applyAndLog(
        txn,
        callId: callId,
        payload: {
          'lansweeper_state': 'sent',
          'lansweeper_main_ticket_id': ticketId,
          'lansweeper_last_sync_at': nowIso,
        },
        action: 'ΚΑΤΑΧΩΡΗΣΗ ΣΤΟ LANSWEEPER',
        // Η υποβολή μέσω API φυλάγεται ανάντη: πριν στείλει, διαβάζει φρέσκια
        // την κλήση και ενημερώνει το υπάρχον αίτημα αντί να ανοίξει δεύτερο.
        // Ένας δεύτερος έλεγχος εδώ θα απέρριπτε ticket που μόλις γεννήθηκε.
        expected: null,
      );
      // Ο σύνδεσμος ακολουθεί την αλλαγή, δεν την προηγείται: επανασήμανση με
      // τον ΙΔΙΟ αριθμό δεν άλλαξε τίποτα, οπότε δεν προσθέτει δεύτερη
      // πανομοιότυπη εγγραφή. Το ιστορικό συνδέσμων είναι που κάνει ανακτήσιμη
      // τη ζημιά όταν δύο άνθρωποι καταχωρούν την ίδια κλήση — διπλότυπα το
      // δυσκολεύουν ακριβώς τη στιγμή που χρειάζεται.
      if (!changed) return;
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
