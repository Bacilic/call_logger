import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/lansweeper_sync_service.dart';
import '../models/lansweeper_sync_state.dart';
import 'dashboard_provider.dart';

class LansweeperSubmitInput {
  const LansweeperSubmitInput({
    required this.title,
    required this.notes,
    required this.solution,
    required this.agentUsername,
    this.durationSeconds,
  });

  final String title;
  final String notes;
  final String solution;
  final String agentUsername;
  final int? durationSeconds;
}

class LansweeperCommandResult {
  const LansweeperCommandResult({
    required this.success,
    required this.message,
    this.ticketId,
    this.ignored = false,
    this.failureReport,
  });

  final bool success;
  final String message;
  final String? ticketId;
  final bool ignored;
  final String? failureReport;
}

class LansweeperSyncNotifier extends AsyncNotifier<void> {
  bool _isRunning = false;

  @override
  FutureOr<void> build() {}

  Future<LansweeperCommandResult> submitCall({
    required int callId,
    required LansweeperSubmitInput input,
    List<int> companionCallIds = const <int>[],
  }) async {
    if (_isRunning) {
      return const LansweeperCommandResult(
        success: false,
        ignored: true,
        message: 'Υπάρχει ήδη ενεργή αποστολή. Περίμενε να ολοκληρωθεί.',
      );
    }

    _isRunning = true;
    state = const AsyncLoading();
    try {
      final db = await DatabaseHelper.instance.database;
      final repo = CallsRepository(db);
      final call = await repo.getCallById(callId);
      if (call == null) {
        state = const AsyncData(null);
        return LansweeperCommandResult(
          success: false,
          message: 'Δεν βρέθηκε η κλήση για αποστολή.',
          failureReport: _buildFailureReport(
            stage: 'call_lookup',
            callId: callId,
            message: 'Δεν βρέθηκε η κλήση για αποστολή.',
          ),
        );
      }

      final service = LansweeperSyncService();
      final result = await service.submitAddTicket(
        LansweeperSyncRequest(
          call: call,
          title: input.title,
          notes: input.notes,
          solution: input.solution,
          agentUsername: input.agentUsername,
          durationSeconds: input.durationSeconds,
        ),
      );

      if (result.success && (result.ticketId?.trim().isNotEmpty ?? false)) {
        final ticketId = result.ticketId!.trim();
        await repo.markLansweeperSynced(
          callId: callId,
          ticketId: ticketId,
          provider: 'lansweeper',
          metadata: <String, dynamic>{
            'mode': 'api',
            'message': result.message,
            'payload': result.rawPayload,
          },
        );
        for (final companionId in companionCallIds) {
          if (companionId == callId) continue;
          await repo.markLansweeperSynced(
            callId: companionId,
            ticketId: ticketId,
            provider: 'lansweeper',
            metadata: <String, dynamic>{
              'mode': 'api_batch',
              'message': result.message,
              'payload': result.rawPayload,
              'primaryCallId': callId,
            },
          );
        }
        if (ref.mounted) {
          state = const AsyncData(null);
        }
        _invalidateDashboardData();
        return LansweeperCommandResult(
          success: true,
          message: result.message,
          ticketId: result.ticketId,
        );
      }

      await repo.updateLansweeperState(
        callId: callId,
        state: LansweeperSyncState.failed,
      );
      if (result.ticketId?.trim().isNotEmpty ?? false) {
        await repo.addExternalLink(
          callId: callId,
          externalId: result.ticketId!.trim(),
          provider: 'lansweeper',
          metadata: <String, dynamic>{
            'mode': 'api_failed',
            'message': result.message,
            'payload': result.rawPayload,
          },
        );
      }
      state = const AsyncData(null);
      _invalidateDashboardData();
      return LansweeperCommandResult(
        success: false,
        message: result.message,
        ticketId: result.ticketId,
        failureReport: _buildFailureReport(
          stage: 'api_response',
          callId: callId,
          message: result.message,
          ticketId: result.ticketId,
          payload: result.rawPayload,
        ),
      );
    } on LansweeperSyncPrecheckException catch (e) {
      state = const AsyncData(null);
      return LansweeperCommandResult(
        success: false,
        message: e.message,
      );
    } catch (e, st) {
      state = AsyncError(e, st);
      final db = await DatabaseHelper.instance.database;
      await CallsRepository(db).updateLansweeperState(
        callId: callId,
        state: LansweeperSyncState.failed,
      );
      _invalidateDashboardData();
      return LansweeperCommandResult(
        success: false,
        message: e.toString(),
        failureReport: _buildFailureReport(
          stage: 'exception',
          callId: callId,
          message: e.toString(),
          stackTrace: st,
        ),
      );
    } finally {
      _isRunning = false;
    }
  }

  Future<LansweeperCommandResult> resubmitCall({
    required int callId,
    required LansweeperSubmitInput input,
    List<int> companionCallIds = const <int>[],
  }) async {
    return submitCall(
      callId: callId,
      input: input,
      companionCallIds: companionCallIds,
    );
  }

  Future<void> markAsPassedManually({
    required int callId,
    required String ticketId,
    String? comment,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    state = const AsyncLoading();
    try {
      final db = await DatabaseHelper.instance.database;
      await CallsRepository(db).markManualPassed(
        callId: callId,
        ticketId: ticketId.trim(),
        comment: comment,
      );
      state = const AsyncData(null);
      _invalidateDashboardData();
    } catch (e, st) {
      state = AsyncError(e, st);
    } finally {
      _isRunning = false;
    }
  }

  Future<void> setExcluded(int callId) =>
      _setState(callId, LansweeperSyncState.excluded);

  Future<void> setUnsent(int callId, {bool retainTicketId = false}) async {
    final db = await DatabaseHelper.instance.database;
    await CallsRepository(db).updateLansweeperState(
      callId: callId,
      state: LansweeperSyncState.unsent,
      clearTicketId: !retainTicketId,
    );
    _invalidateDashboardData();
  }

  Future<int> countRegisteredCallsWithTicketId(
    String ticketId, {
    required int excludeCallId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return CallsRepository(db).countCallsWithLansweeperTicketId(
      ticketId,
      excludeCallId: excludeCallId,
      registeredOnly: true,
    );
  }

  Future<String?> suggestedNextLansweeperTicketId() async {
    final db = await DatabaseHelper.instance.database;
    return CallsRepository(db).suggestedNextLansweeperTicketId();
  }

  Future<void> setSent(int callId, {String? ticketId}) async {
    final normalized = ticketId?.trim() ?? '';
    if (normalized.isEmpty) {
      await _setState(callId, LansweeperSyncState.sent);
      return;
    }
    final db = await DatabaseHelper.instance.database;
    await CallsRepository(db).updateLansweeperState(
      callId: callId,
      state: LansweeperSyncState.sent,
      ticketId: normalized,
      updateTicketId: true,
    );
    _invalidateDashboardData();
  }

  /// Χειροκίνητη καταχώρηση· το ticket id είναι προαιρετικό.
  Future<void> markRegistered({
    required int callId,
    String? ticketId,
    String? comment,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    state = const AsyncLoading();
    try {
      final normalized = ticketId?.trim() ?? '';
      final db = await DatabaseHelper.instance.database;
      final repo = CallsRepository(db);
      if (normalized.isEmpty) {
        await repo.updateLansweeperState(
          callId: callId,
          state: LansweeperSyncState.sent,
        );
      } else {
        await repo.markManualPassed(
          callId: callId,
          ticketId: normalized,
          comment: comment,
        );
      }
      state = const AsyncData(null);
      _invalidateDashboardData();
    } catch (e, st) {
      state = AsyncError(e, st);
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _setState(int callId, String nextState) async {
    final db = await DatabaseHelper.instance.database;
    await CallsRepository(
      db,
    ).updateLansweeperState(callId: callId, state: nextState);
    _invalidateDashboardData();
  }

  void _invalidateDashboardData() {
    ref.invalidate(dashboardCallsForReportProvider);
    ref.invalidate(dashboardStatsProvider);
  }

  String _buildFailureReport({
    required String stage,
    required int callId,
    required String message,
    String? ticketId,
    Map<String, dynamic>? payload,
    StackTrace? stackTrace,
  }) {
    final lines = <String>[
      'Lansweeper submit failed',
      'stage: $stage',
      'callId: $callId',
      'message: $message',
      'timestamp: ${DateTime.now().toIso8601String()}',
    ];

    final normalizedTicketId = (ticketId ?? '').trim();
    if (normalizedTicketId.isNotEmpty) {
      lines.add('ticketId: $normalizedTicketId');
    }

    if (payload != null) {
      try {
        final encoder = const JsonEncoder.withIndent('  ');
        lines.add('payload:\n${encoder.convert(payload)}');
      } catch (_) {
        lines.add('payload: ${payload.toString()}');
      }
    }

    if (stackTrace != null) {
      lines.add('stackTrace:\n$stackTrace');
    }

    return lines.join('\n');
  }
}

final lansweeperSyncProvider =
    AsyncNotifierProvider.autoDispose<LansweeperSyncNotifier, void>(
      LansweeperSyncNotifier.new,
    );

final callExternalLinksProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, callId) async {
      final db = await DatabaseHelper.instance.database;
      return CallsRepository(
        db,
      ).getCallExternalLinks(callId, provider: 'lansweeper');
    });
