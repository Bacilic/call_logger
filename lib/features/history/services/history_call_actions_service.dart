import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../calls/models/call_model.dart';
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

  Future<CallModel?> getCallById(int callId) async {
    final repo = await _repo();
    return repo.getCallById(callId);
  }

  Future<int> countLinkedTasks(int callId) async {
    final repo = await _repo();
    return repo.getTasksCountLinkedToCall(callId);
  }

  Future<int> countLinkedTasksForCalls(List<int> callIds) async {
    final repo = await _repo();
    return repo.getTasksCountLinkedToCalls(callIds);
  }

  Future<void> saveEditedCall(CallModel call) async {
    final repo = await _repo();
    await repo.updateCall(call);
    await refreshAfterMutation(
      callerId: call.callerId,
      equipmentCode: call.equipmentText,
    );
  }

  Future<void> deleteCall(
    int callId, {
    required String taskAction,
    bool hard = false,
    int? callerId,
    String? equipmentCode,
  }) async {
    final repo = await _repo();
    await repo.deleteCallWithTasksAction(callId, taskAction, hard: hard);
    await refreshAfterMutation(
      callerId: callerId,
      equipmentCode: equipmentCode,
    );
  }

  Future<void> hardDeleteCall(
    int callId, {
    int? callerId,
    String? equipmentCode,
  }) async {
    final repo = await _repo();
    await repo.hardDeleteCall(callId);
    await refreshAfterMutation(
      callerId: callerId,
      equipmentCode: equipmentCode,
    );
  }

  Future<void> bulkSoftDelete(List<int> callIds, {String? taskAction}) async {
    final repo = await _repo();
    await repo.bulkSoftDeleteCalls(callIds, taskAction: taskAction);
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
  }
}
