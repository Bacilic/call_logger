import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/call_deletion_impact.dart';
import '../../../core/database/calls_deletion_repository.dart';
import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/utils/run_after_next_frame.dart';
import '../../calls/models/call_model.dart';
import '../../calls/services/call_save_conflict.dart';
import '../../calls/provider/calls_dashboard_providers.dart';
import '../../tasks/providers/tasks_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/history_provider.dart';

class HistoryCallActionsService {
  HistoryCallActionsService(this.ref);

  final Ref ref;

  Future<CallsRepository> _repo() async {
    final db = await DatabaseHelper.instance.database;
    return CallsRepository(db);
  }

  Future<CallsDeletionRepository> _deletion() async {
    final db = await DatabaseHelper.instance.database;
    return CallsDeletionRepository(db);
  }

  Future<CallModel?> getCallById(int callId) async {
    final repo = await _repo();
    return repo.getCallById(callId);
  }

  Future<CallDeletionImpact> callDeletionImpact(List<int> callIds) async {
    final deletion = await _deletion();
    return deletion.getCallDeletionImpact(callIds);
  }

  /// Αποθηκεύει επεξεργασμένη κλήση.
  ///
  /// Το [expected] είναι η κλήση **όπως τη φόρτωσε ο διάλογος**: η ενημέρωση
  /// γράφει ολόκληρη τη γραμμή, μαζί με τα πεδία Lansweeper, οπότε χωρίς
  /// αφετηρία μια διόρθωση κειμένου σβήνει την καταχώρηση του συναδέλφου.
  ///
  /// Πετά [CallStaleException] όταν κάποιος πρόλαβε — ο καλών ρωτά τον χρήστη
  /// και, αν εκείνος επιμείνει, ξανακαλεί με [force].
  Future<void> saveEditedCall(
    CallModel call, {
    required CallModel? expected,
    bool force = false,
  }) async {
    final repo = await _repo();
    await repo.updateCall(call, expected: expected, force: force);
    await refreshAfterMutation(
      callerId: call.callerId,
      equipmentCode: call.equipmentText,
    );
  }

  /// Η διένεξη ντυμένη με το «ποιος και πότε» από το Ιστορικό.
  Future<CallSaveConflict> describeConflict(CallSaveConflict conflict) async {
    final repo = await _repo();
    final id = conflict.fresh.id;
    if (id == null) return conflict;
    final actor = await repo.lastActorFor(id);
    return CallSaveConflict(
      expected: conflict.expected,
      fresh: conflict.fresh,
      attempted: conflict.attempted,
      changedBy: actor.who,
      changedAt: actor.at,
    );
  }

  /// Διαγραφή κλήσης — το [hard] αλλάζει πόσο βαθιά σβήνει, ποτέ τι θα γίνουν
  /// οι εκκρεμότητες: αυτό το λέει πάντα το [taskAction] του χρήστη.
  Future<void> deleteCall(
    int callId, {
    required String taskAction,
    bool hard = false,
    int? callerId,
    String? equipmentCode,
  }) async {
    final deletion = await _deletion();
    await deletion.deleteCallWithTasksAction(callId, taskAction, hard: hard);
    await refreshAfterMutation(
      callerId: callerId,
      equipmentCode: equipmentCode,
    );
  }

  /// Μαζική διαγραφή — το [hard] αλλάζει πόσο βαθιά σβήνει, ποτέ τι θα γίνουν
  /// οι εκκρεμότητες: αυτό το λέει πάντα το [taskAction] του χρήστη.
  Future<void> bulkDelete(
    List<int> callIds, {
    String? taskAction,
    bool hard = false,
  }) async {
    final deletion = await _deletion();
    await deletion.bulkDeleteCalls(callIds, taskAction: taskAction, hard: hard);
    await refreshAfterMutation();
  }

  Future<int> cloneCall(int callId) async {
    final repo = await _repo();
    final newCallId = await repo.cloneCall(callId);
    await refreshAfterMutation();
    return newCallId;
  }

  Future<void> refreshAfterMutation({
    int? callerId,
    String? equipmentCode,
  }) async {
    if (!ref.mounted) return;
    return runAfterNextFrame(() {
      if (!ref.mounted) return;
      ref.invalidate(historyCallsProvider);
      ref.invalidate(historyCategoryDateCallCountProvider);
      ref.invalidate(globalRecentCallsProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(tasksProvider);

      if (callerId != null) {
        ref.invalidate(recentCallsProvider(callerId));
      }
      final code = equipmentCode?.trim();
      if (code != null && code.isNotEmpty) {
        ref.invalidate(recentCallsByEquipmentProvider(code));
      }
    });
  }
}
