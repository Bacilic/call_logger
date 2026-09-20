import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/tasks/models/task.dart';
import 'audit_service.dart';
import 'tasks_repository.dart';

/// Πού βρίσκεται μία εκκρεμότητα απέναντι στο Lansweeper, διαβασμένο φρέσκο.
class TaskLansweeperSnapshot {
  const TaskLansweeperSnapshot({
    required this.taskId,
    required this.state,
    required this.ticketId,
    required this.lastSyncAt,
    this.title = '',
  });

  final int taskId;
  final String state;

  /// Ο αριθμός του αιτήματος· κενός όταν δεν έχει σταλεί ποτέ.
  final String ticketId;

  final String? lastSyncAt;

  /// Ο τίτλος της εκκρεμότητας, για να την ονομάσει ο διάλογος στον χρήστη.
  ///
  /// Ταξιδεύει μαζί με το στιγμιότυπο ώστε ο καλών να μη χρειάζεται δεύτερη
  /// ανάγνωση — και, κυρίως, ώστε να μη χρειάζεται να ξέρει ότι υπάρχει
  /// πίνακας `tasks`. Κενός όταν η γραμμή δεν τον έφερε.
  final String title;

  bool get hasTicket => ticketId.isNotEmpty;
}

/// Η **μοναδική πόρτα εγγραφής** για την κατάσταση Lansweeper των εκκρεμοτήτων.
///
/// Χωριστά από το `TasksRepository` επίτηδες, και όχι επειδή εκείνο είναι
/// μεγάλο: η αποθήκευση της φόρμας γράφει **ολόκληρη** την καρτέλα, ενώ αυτές
/// οι τρεις στήλες πρέπει να γράφονται **μόνες τους**. Ανακατεμένες στην ίδια
/// διαδρομή, μια επεξεργασία τίτλου θα έσβηνε σιωπηλά το αίτημα που μόλις
/// κατέγραψε συνάδελφος από άλλον σταθμό.
class TasksLansweeperRepository {
  TasksLansweeperRepository(this.db);

  final Database db;

  /// Οι τιμές που δέχεται η στήλη `lansweeper_state`.
  ///
  /// Το ίδιο λεξιλόγιο με τις κλήσεις, ώστε η κατάσταση να διαβάζεται από τον
  /// ίδιο κώδικα και να γράφεται με τις ίδιες λέξεις στην οθόνη. Η εκκρεμότητα
  /// χρησιμοποιεί σήμερα μόνο τις τρεις πρώτες — δεν έχει ουρά να την εξαιρέσει
  /// κανείς.
  static const String stateUnsent = 'unsent';
  static const String stateSent = 'sent';
  static const String stateFailed = 'failed';

  /// Τι βρίσκεται **τώρα** στη βάση για αυτή την εκκρεμότητα.
  ///
  /// `null` σημαίνει ότι η εκκρεμότητα δεν υπάρχει (ή διαγράφηκε) — ο καλών
  /// οφείλει να το ξεχωρίσει από το «υπάρχει και δεν έχει σταλεί».
  Future<TaskLansweeperSnapshot?> readState(int taskId) async {
    final rows = await db.query(
      'tasks',
      columns: const [
        'id',
        'lansweeper_state',
        'lansweeper_main_ticket_id',
        'lansweeper_last_sync_at',
      ],
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _snapshotOf(rows.first);
  }

  /// Οι εκκρεμότητες μιας κλήσης που έχουν **ήδη** δικό τους αίτημα.
  ///
  /// Το ερώτημα της αντίστροφης κατεύθυνσης: πριν σταλεί μια κλήση, πρέπει να
  /// φανεί αν κάποια εκκρεμότητά της πρόλαβε να γίνει αίτημα. Οι διαγραμμένες
  /// μένουν έξω — δεν είναι δουλειά που περιμένει κανέναν.
  Future<List<TaskLansweeperSnapshot>> ticketedTasksForCall(int callId) async {
    final rows = await db.query(
      'tasks',
      columns: const [
        'id',
        'title',
        'lansweeper_state',
        'lansweeper_main_ticket_id',
        'lansweeper_last_sync_at',
      ],
      where:
          'call_id = ? AND COALESCE(is_deleted, 0) = 0 '
          "AND TRIM(COALESCE(lansweeper_main_ticket_id, '')) <> ''",
      whereArgs: [callId],
      orderBy: 'id ASC',
    );
    return [for (final row in rows) _snapshotOf(row)];
  }

  /// Η εκκρεμότητα έγινε αίτημα — κρατά τον αριθμό και την ώρα.
  ///
  /// Επιστρέφει `false` όταν δεν άλλαξε τίποτα (η ίδια κατάσταση με τον ίδιο
  /// αριθμό): τότε δεν γράφεται ούτε εγγραφή στο Ιστορικό, γιατί μια δεύτερη
  /// πανομοιότυπη γραμμή δεν λέει τίποτα που δεν λέει ήδη η πρώτη.
  Future<bool> markSubmitted({required int taskId, required String ticketId}) {
    final trimmed = ticketId.trim();
    return _apply(
      taskId: taskId,
      state: stateSent,
      ticketId: trimmed,
      action: 'ΚΑΤΑΧΩΡΗΣΗ ΕΚΚΡΕΜΟΤΗΤΑΣ ΣΤΟ LANSWEEPER',
    );
  }

  /// Η αποστολή απέτυχε.
  ///
  /// Ο αριθμός **δεν καθαρίζεται**: όταν το αίτημα είχε ήδη δημιουργηθεί και
  /// έσπασε κάποιο επόμενο βήμα, ο αριθμός είναι ακριβώς η πληροφορία που
  /// χρειάζεται ο άνθρωπος για να συνεχίσει με το χέρι. Σβήνοντάς τον θα
  /// αφήναμε ορφανό αίτημα στο Lansweeper, που η εφαρμογή δεν μπορεί να βρει.
  Future<bool> markFailed({required int taskId, String? ticketId}) {
    return _apply(
      taskId: taskId,
      state: stateFailed,
      ticketId: ticketId?.trim(),
      action: 'ΑΠΟΤΥΧΙΑ ΑΠΟΣΤΟΛΗΣ ΕΚΚΡΕΜΟΤΗΤΑΣ ΣΤΟ LANSWEEPER',
    );
  }

  /// Θα άλλαζε πράγματι κάτι η [saveTexts] με αυτά τα κείμενα;
  ///
  /// Ζει **δίπλα στην εγγραφή και τηρεί τους ίδιους κανόνες** — κενό πεδίο δεν
  /// αγγίζει ό,τι υπάρχει, και τρία κενά πεδία δεν γράφουν τίποτα. Αν η
  /// απάντηση εδώ αποκλίνει από τη συμπεριφορά της εγγραφής, το κουμπί που τη
  /// ρωτά θα λέει ψέματα: είτε θα δηλώνει «αποθηκεύτηκε» χωρίς να αλλάξει
  /// τίποτα, είτε θα μένει ανενεργό ενώ υπάρχει δουλειά να σωθεί.
  static bool wouldChangeTexts({
    required String title,
    required String problem,
    required String solution,
    required Task current,
  }) {
    bool differs(String candidate, String? stored) {
      final trimmed = candidate.trim();
      return trimmed.isNotEmpty && trimmed != (stored ?? '').trim();
    }

    return differs(title, current.title) ||
        differs(problem, current.description) ||
        differs(solution, current.solutionNotes);
  }

  /// Γράφει το δουλεμένο κείμενο πάνω στην εκκρεμότητα — και **τίποτα άλλο**.
  ///
  /// Η αντιστοίχιση είναι ένα προς ένα, σε αντίθεση με την κλήση: η εκκρεμότητα
  /// έχει δικό της τίτλο, οπότε δεν χρειάζεται να στριμωχτεί ο τίτλος μαζί με
  /// την περιγραφή σε ένα πεδίο.
  ///
  /// Καλείται **μόνο** από ρητό πάτημα του χρήστη. Η αποστολή στο Lansweeper
  /// δεν περνά ποτέ από εδώ: το κείμενο της εκκρεμότητας είναι γραμμένο από
  /// άνθρωπο και δεν αντικαθίσταται σιωπηλά από ό,τι διατύπωσε η ΤΝ για το
  /// helpdesk.
  ///
  /// Κενό πεδίο αφήνει ό,τι υπάρχει: μια φόρμα που δεν συμπληρώθηκε δεν σβήνει
  /// δουλειά.
  Future<bool> saveTexts({
    required int taskId,
    required String title,
    required String problem,
    required String solution,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedProblem = problem.trim();
    final trimmedSolution = solution.trim();
    final payload = <String, Object?>{
      if (trimmedTitle.isNotEmpty) 'title': trimmedTitle,
      if (trimmedProblem.isNotEmpty) 'description': trimmedProblem,
      if (trimmedSolution.isNotEmpty) 'solution_notes': trimmedSolution,
    };
    if (payload.isEmpty) return false;

    final changed = await db.transaction<bool>((txn) async {
      final rows = await txn.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final before = rows.first;
      final current = Task.fromMap(before);
      if (!wouldChangeTexts(
        title: title,
        problem: problem,
        solution: solution,
        current: current,
      )) {
        return false;
      }

      await txn.update(
        'tasks',
        {...payload, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [taskId],
      );

      final oldValues = <String, dynamic>{};
      final newValues = <String, dynamic>{};
      for (final field in payload.keys) {
        final was = '${before[field] ?? ''}';
        final now = '${payload[field] ?? ''}';
        if (was == now) continue;
        oldValues[field] = before[field];
        newValues[field] = payload[field];
      }
      if (newValues.isEmpty) return false;

      await AuditService.log(
        txn,
        action: 'ΕΝΗΜΕΡΩΣΗ ΚΕΙΜΕΝΟΥ ΕΚΚΡΕΜΟΤΗΤΑΣ ΑΠΟ ΦΟΡΜΑ LANSWEEPER',
        userPerforming: AuditService.performingUser(),
        details: 'tasks id=$taskId',
        entityType: AuditEntityTypes.task,
        entityId: taskId,
        entityName: newValues['title']?.toString() ?? current.title,
        oldValues: oldValues,
        newValues: newValues,
      );
      return true;
    });

    // Το ευρετήριο αναζήτησης χτίζεται από τα ίδια κείμενα: χωρίς αυτό η
    // εκκρεμότητα θα έμενε εύρετη μόνο με τις παλιές της λέξεις.
    if (changed) await TasksRepository().rebuildSearchIndexForTaskId(taskId);
    return changed;
  }

  TaskLansweeperSnapshot _snapshotOf(Map<String, Object?> row) {
    final raw = (row['lansweeper_state'] as String?)?.trim() ?? '';
    return TaskLansweeperSnapshot(
      taskId: row['id'] as int,
      // Κενό ή άγνωστο σημαίνει «δεν στάλθηκε»: εγγραφή γραμμένη από παλαιότερη
      // έκδοση δεν επιτρέπεται να εμφανιστεί σε άγνωστη κατάσταση.
      state: raw.isEmpty ? stateUnsent : raw,
      ticketId: (row['lansweeper_main_ticket_id'] as String?)?.trim() ?? '',
      lastSyncAt: row['lansweeper_last_sync_at'] as String?,
      title: (row['title'] as String?)?.trim() ?? '',
    );
  }

  /// Γράφει τις τρεις στήλες και καταγράφει **μόνο ό,τι όντως άλλαξε**.
  ///
  /// Η ώρα συγχρονισμού μένει έξω από το Ιστορικό επίτηδες: αλλάζει σε κάθε
  /// εγγραφή και θα έπνιγε τη γραμμή σε θόρυβο, χωρίς να απαντά κάτι που δεν
  /// απαντά ήδη η χρονοσφραγίδα της ίδιας της εγγραφής Ιστορικού.
  ///
  /// `null` [ticketId] σημαίνει «άσε τον αριθμό όπως τον βρεις», όχι
  /// «καθάρισέ τον».
  Future<bool> _apply({
    required int taskId,
    required String state,
    required String? ticketId,
    required String action,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    return db.transaction<bool>((txn) async {
      final rows = await txn.query(
        'tasks',
        columns: const [
          'id',
          'title',
          'lansweeper_state',
          'lansweeper_main_ticket_id',
        ],
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final before = rows.first;

      final oldState =
          (before['lansweeper_state'] as String?)?.trim().isNotEmpty == true
          ? (before['lansweeper_state'] as String).trim()
          : stateUnsent;
      final oldTicket =
          (before['lansweeper_main_ticket_id'] as String?)?.trim() ?? '';
      final newTicket = ticketId ?? oldTicket;

      if (oldState == state && oldTicket == newTicket) return false;

      await txn.update(
        'tasks',
        {
          'lansweeper_state': state,
          'lansweeper_main_ticket_id': newTicket.isEmpty ? null : newTicket,
          'lansweeper_last_sync_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [taskId],
      );

      final oldValues = <String, dynamic>{};
      final newValues = <String, dynamic>{};
      if (oldState != state) {
        oldValues['lansweeper_state'] = oldState;
        newValues['lansweeper_state'] = state;
      }
      if (oldTicket != newTicket) {
        oldValues['lansweeper_main_ticket_id'] = oldTicket;
        newValues['lansweeper_main_ticket_id'] = newTicket;
      }

      await AuditService.log(
        txn,
        action: action,
        userPerforming: AuditService.performingUser(),
        details: 'tasks id=$taskId',
        entityType: AuditEntityTypes.task,
        entityId: taskId,
        entityName: before['title']?.toString(),
        oldValues: oldValues.isEmpty ? null : oldValues,
        newValues: newValues.isEmpty ? null : newValues,
      );
      return true;
    });
  }
}
