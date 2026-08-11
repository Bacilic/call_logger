import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_lansweeper_repository.dart';
import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/providers/active_critical_operations_provider.dart';
import '../../../core/services/lansweeper_asset_target.dart';
import '../../../core/services/lansweeper_department_accounts.dart';
import '../../../core/services/lansweeper_requester_resolution.dart';
import '../../../core/services/lansweeper_sync_service.dart';
import '../../../core/services/lansweeper_ticket_submit_config.dart';
import '../../../core/services/lookup_service.dart';
import '../../calls/models/call_model.dart';
import '../../calls/provider/call_mutation_refresh.dart';
import '../models/lansweeper_sync_state.dart';

final lansweeperSyncServiceProvider = Provider<LansweeperSyncService>(
  (ref) => LansweeperSyncService(),
);

class LansweeperSubmitInput {
  const LansweeperSubmitInput({
    required this.title,
    required this.notes,
    required this.solution,
    required this.agentUsername,
    required this.refinedSource,
    this.durationSeconds,
    this.customFieldValues = const <String, String>{},
    this.targetTicketState,
    this.config,
    this.requesterUsername,
  });

  final String title;
  final String notes;
  final String solution;
  final String agentUsername;

  /// Πώς προέκυψε το κείμενο ([CallRefinedSource]) — ταξιδεύει μαζί του ώστε η
  /// κλήση να θυμάται αν το έγραψε η ΤΝ, αν το διορθώσατε ή αν είναι δικό σας.
  final String refinedSource;
  final int? durationSeconds;
  final Map<String, String> customFieldValues;
  final String? targetTicketState;
  final LansweeperTicketSubmitConfig? config;

  /// Ο αιτών που έδειχνε η φόρμα τη στιγμή της αποστολής.
  ///
  /// `null` = η φόρμα δεν είχε άποψη, οπότε αποφασίζει η αυτόματη ιεραρχία.
  /// Κενό κείμενο = ρητή επιλογή «χωρίς αιτούντα» — μπαίνει ο πράκτορας.
  final String? requesterUsername;
}

class LansweeperCommandResult {
  const LansweeperCommandResult({
    required this.success,
    required this.message,
    this.ticketId,
    this.ignored = false,
    this.failureReport,
    this.warnings = const <String>[],
    this.completedSteps = const <String>[],
    this.failedStep,
  });

  final bool success;
  final String message;
  final String? ticketId;
  final bool ignored;
  final String? failureReport;
  final List<String> warnings;
  final List<String> completedSteps;
  final String? failedStep;
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
    final criticalOps = ref.read(activeCriticalOperationsProvider.notifier);
    criticalOps.begin(CriticalOperation.lansweeperTicketSubmit);
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

      if (input.agentUsername.trim().isEmpty) {
        state = const AsyncData(null);
        return const LansweeperCommandResult(
          success: false,
          message: 'Ο πράκτορας API (AgentUsername) είναι υποχρεωτικός.',
        );
      }

      final config = input.config ?? LansweeperTicketSubmitConfig.defaults();
      final existingTicketIdRaw = (call.lansweeperMainTicketId ?? '').trim();
      final existingTicketId = existingTicketIdRaw.isEmpty
          ? null
          : existingTicketIdRaw;
      final targetState = (input.targetTicketState?.trim().isNotEmpty ?? false)
          ? input.targetTicketState!.trim()
          : config.defaultTicketState;

      // Αναγνωριστικά της συνδεδεμένης κλήσης: ο υπάλληλος ως αιτών και ο
      // εξοπλισμός ως asset. Κλήση με ελεύθερο κείμενο (χωρίς σύνδεση στον
      // Κατάλογο) δεν έχει τίποτα να δώσει — η ροή μένει όπως πριν.
      //
      // Ό,τι έδειχνε η φόρμα κερδίζει: εκεί ο χρήστης μπορεί να διάλεξε
      // λογαριασμό τμήματος ή ρητά «χωρίς αιτούντα», και η επιλογή του δεν
      // επιτρέπεται να παρακαμφθεί από την αυτόματη ιεραρχία.
      final String? requesterUsername;
      final formChoice = input.requesterUsername;
      if (formChoice != null) {
        final chosen = formChoice.trim();
        requesterUsername = chosen.isEmpty ? null : chosen;
      } else {
        final callerId = call.callerId;
        requesterUsername = callerId == null
            ? null
            : await UserRepository(db).getLansweeperUsernameById(callerId);
      }
      final equipmentId = call.equipmentId;
      LansweeperAssetTarget? assetTarget;
      if (equipmentId != null) {
        final assetFields = await EquipmentRepository(
          db,
        ).getLansweeperAssetFieldsById(equipmentId);
        if (assetFields != null) {
          assetTarget = lansweeperAssetTargetFor(
            storedAssetName: assetFields.assetName,
            equipmentCode: assetFields.code,
          );
        }
      }

      final service = ref.read(lansweeperSyncServiceProvider);
      final result = await service.submitTicketWorkflow(
        LansweeperWorkflowRequest(
          call: call,
          title: input.title,
          problem: input.notes,
          solution: input.solution,
          agentUsername: input.agentUsername,
          durationSeconds: input.durationSeconds,
          config: config,
          customFieldValues: input.customFieldValues,
          targetState: targetState,
          existingTicketId: existingTicketId,
          requesterUsername: requesterUsername,
          assetTarget: assetTarget,
        ),
      );

      // CONTRACT: κάθε εγγραφή ΜΕΤΑ από μακρύ `await` (εδώ: το HTTP workflow που
      // κρατά δευτερόλεπτα) χρησιμοποιεί ΦΡΕΣΚΟ handle βάσης. Το `repo` παραπάνω
      // δεσμεύτηκε πριν την αποστολή· αν η βάση εναλλάχθηκε στο μεταξύ, γράφοντας
      // με εκείνο θα αποτύγχανε (database_closed) ή θα έγραφε σε λάθος στόχο —
      // με το εισιτήριο ΗΔΗ δημιουργημένο στο Lansweeper, δηλαδή κίνδυνος διπλής
      // αποστολής. (Ο φρουρός εναλλαγής μπλοκάρει ήδη το σενάριο· αυτό εδώ κλείνει
      // τη ρίζα, ώστε να μην εξαρτάται η ορθότητα από τον φρουρό.)
      final writeDb = await DatabaseHelper.instance.database;
      final writeRepo = CallsLansweeperRepository(writeDb);

      if (result.success && (result.ticketId?.trim().isNotEmpty ?? false)) {
        final ticketId = result.ticketId!.trim();
        // Πριν από κάθε άλλη εγγραφή: το κείμενο μόλις έφυγε στο ticket στην πιο
        // έγκυρη μορφή του — περασμένο από την ΤΝ και από το μάτι του χρήστη.
        await writeRepo.saveRefinedTexts(
          callIds: <int>[callId, ...companionCallIds],
          problem: input.notes,
          solution: input.solution,
          source: input.refinedSource,
        );
        await writeRepo.markLansweeperSynced(
          callId: callId,
          ticketId: ticketId,
          provider: 'lansweeper',
          metadata: <String, dynamic>{
            'mode': 'api_workflow',
            'message': result.message,
            'completedSteps': result.completedSteps,
            'warnings': result.warnings,
            'failedStep': result.failedStep,
            'payload': result.rawPayloads,
          },
        );
        for (final companionId in companionCallIds) {
          if (companionId == callId) continue;
          await writeRepo.markLansweeperSynced(
            callId: companionId,
            ticketId: ticketId,
            provider: 'lansweeper',
            metadata: <String, dynamic>{
              'mode': 'api_workflow_batch',
              'message': result.message,
              'completedSteps': result.completedSteps,
              'warnings': result.warnings,
              'failedStep': result.failedStep,
              'payload': result.rawPayloads,
              'primaryCallId': callId,
            },
          );
        }
        if (ref.mounted) {
          state = const AsyncData(null);
        }
        _refreshAfterLansweeperMutation();
        return LansweeperCommandResult(
          success: true,
          message: result.message,
          ticketId: result.ticketId,
          warnings: result.warnings,
          completedSteps: result.completedSteps,
        );
      }

      await writeRepo.updateLansweeperState(
        callId: callId,
        state: LansweeperSyncState.failed,
      );
      if (result.ticketId?.trim().isNotEmpty ?? false) {
        await writeRepo.addExternalLink(
          callId: callId,
          externalId: result.ticketId!.trim(),
          provider: 'lansweeper',
          metadata: <String, dynamic>{
            'mode': 'api_workflow_failed',
            'message': result.message,
            'completedSteps': result.completedSteps,
            'warnings': result.warnings,
            'failedStep': result.failedStep,
            'payload': result.rawPayloads,
          },
        );
      }
      state = const AsyncData(null);
      _refreshAfterLansweeperMutation();
      return LansweeperCommandResult(
        success: false,
        message: result.message,
        ticketId: result.ticketId,
        warnings: result.warnings,
        completedSteps: result.completedSteps,
        failedStep: result.failedStep,
        failureReport: _buildFailureReport(
          stage: result.failedStep ?? 'workflow',
          callId: callId,
          message: result.message,
          ticketId: result.ticketId,
          payload: result.rawPayloads,
        ),
      );
    } on LansweeperSyncPrecheckException catch (e) {
      state = const AsyncData(null);
      return LansweeperCommandResult(success: false, message: e.message);
    } catch (e, st) {
      state = AsyncError(e, st);
      final db = await DatabaseHelper.instance.database;
      await CallsLansweeperRepository(db).updateLansweeperState(
        callId: callId,
        state: LansweeperSyncState.failed,
      );
      _refreshAfterLansweeperMutation();
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
      criticalOps.end(CriticalOperation.lansweeperTicketSubmit);
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

  /// Κρατά το καθαρό κείμενο όταν φεύγει από τη φόρμα χωρίς υποβολή API.
  ///
  /// Η «Αντιγραφή & Άνοιγμα» στέλνει το κείμενο στο πρόχειρο και ανοίγει τον
  /// περιηγητή· χωρίς αυτό, η ροή που δουλεύεται καθημερινά θα ήταν η μόνη που
  /// πετά όλη τη δουλειά. Η κατάσταση καταχώρησης δεν αλλάζει — το ticket δεν
  /// έχει δημιουργηθεί ακόμα, το κείμενο όμως υπάρχει και είναι έγκυρο.
  Future<void> persistRefinedTexts({
    required List<int> callIds,
    required String problem,
    required String solution,
    required String source,
  }) async {
    if (callIds.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    await CallsLansweeperRepository(db).saveRefinedTexts(
      callIds: callIds,
      problem: problem,
      solution: solution,
      source: source,
    );
    _refreshAfterLansweeperMutation();
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
      await CallsLansweeperRepository(db).markManualPassed(
        callId: callId,
        ticketId: ticketId.trim(),
        comment: comment,
      );
      state = const AsyncData(null);
      _refreshAfterLansweeperMutation();
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
    await CallsLansweeperRepository(db).updateLansweeperState(
      callId: callId,
      state: LansweeperSyncState.unsent,
      clearTicketId: !retainTicketId,
    );
    _refreshAfterLansweeperMutation();
  }

  Future<int> countRegisteredCallsWithTicketId(
    String ticketId, {
    required int excludeCallId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return CallsLansweeperRepository(db).countCallsWithLansweeperTicketId(
      ticketId,
      excludeCallId: excludeCallId,
      registeredOnly: true,
    );
  }

  Future<String?> suggestedNextLansweeperTicketId() async {
    final db = await DatabaseHelper.instance.database;
    return CallsLansweeperRepository(db).suggestedNextLansweeperTicketId();
  }

  Future<void> setSent(int callId, {String? ticketId}) async {
    final normalized = ticketId?.trim() ?? '';
    if (normalized.isEmpty) {
      await _setState(callId, LansweeperSyncState.sent);
      return;
    }
    final db = await DatabaseHelper.instance.database;
    await CallsLansweeperRepository(db).updateLansweeperState(
      callId: callId,
      state: LansweeperSyncState.sent,
      ticketId: normalized,
      updateTicketId: true,
    );
    _refreshAfterLansweeperMutation();
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
      final repo = CallsLansweeperRepository(db);
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
      _refreshAfterLansweeperMutation();
    } catch (e, st) {
      state = AsyncError(e, st);
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _setState(int callId, String nextState) async {
    final db = await DatabaseHelper.instance.database;
    await CallsLansweeperRepository(
      db,
    ).updateLansweeperState(callId: callId, state: nextState);
    _refreshAfterLansweeperMutation();
  }

  void _refreshAfterLansweeperMutation() {
    refreshAfterCallMutation(ref);
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
      return CallsLansweeperRepository(
        db,
      ).getCallExternalLinks(callId, provider: 'lansweeper');
    });

/// Τι θα μπει αυτόματα στο ticket: ο αιτών (με τους υποψηφίους του, όταν
/// υπάρχει επιλογή) και ο εξοπλισμός.
class LansweeperTicketParties {
  const LansweeperTicketParties({required this.requester, this.asset});

  static const empty = LansweeperTicketParties(
    requester: LansweeperRequesterOptions(
      selectedUsername: null,
      candidates: [],
      isChoosable: false,
    ),
  );

  final LansweeperRequesterOptions requester;

  /// Το όνομα asset που θα συνδεθεί· `null` = χωρίς εξοπλισμό.
  final String? asset;
}

/// Τα «πρόσωπα» του ticket για τις δοσμένες κλήσεις.
///
/// Κλειδί: τα ids χωρισμένα με κόμμα — **η σειρά μετράει**, η πρώτη κλήση
/// είναι η κύρια και δίνει τον εξοπλισμό. Ο αιτών προκύπτει από τον καλούντα
/// της κύριας και, όταν εκείνος δεν έχει αναγνωριστικό, από τα τμήματα **όλων**
/// των κλήσεων του ticket.
final lansweeperTicketPartiesProvider = FutureProvider.autoDispose
    .family<LansweeperTicketParties, String>((ref, callIdsKey) async {
      final callIds = callIdsKey
          .split(',')
          .map((raw) => int.tryParse(raw.trim()))
          .whereType<int>()
          .toList();
      if (callIds.isEmpty) return LansweeperTicketParties.empty;

      final db = await DatabaseHelper.instance.database;
      final callsRepo = CallsRepository(db);
      final calls = <CallModel>[];
      for (final id in callIds) {
        final call = await callsRepo.getCallById(id);
        if (call != null) calls.add(call);
      }
      if (calls.isEmpty) return LansweeperTicketParties.empty;

      final primary = calls.first;

      // Οι ΔΙΑΚΡΙΤΟΙ καλούντες όλων των επιλεγμένων κλήσεων, με σειρά πρώτης
      // εμφάνισης (πρώτος = της κύριας). Κλήσεις χωρίς συνδεδεμένο καλούντα
      // μετρούν ως επιπλέον «πρόσωπο»: κάνουν τον αιτούντα απόφαση.
      final userRepo = UserRepository(db);
      final callers = <LansweeperTicketCaller>[];
      final seenCallerIds = <int>{};
      var hasUnidentifiedCalls = false;
      for (final call in calls) {
        final callerId = call.callerId;
        if (callerId == null) {
          hasUnidentifiedCalls = true;
          continue;
        }
        if (!seenCallerIds.add(callerId)) continue;
        final username = await userRepo.getLansweeperUsernameById(callerId);
        final displayName = (call.callerText ?? '').trim();
        callers.add(
          LansweeperTicketCaller(
            displayName: displayName.isEmpty ? 'Καλών #$callerId' : displayName,
            departmentName: (call.departmentText ?? '').trim(),
            username: username,
          ),
        );
      }
      final partyCount = callers.length + (hasUnidentifiedCalls ? 1 : 0);

      // Τα τμήματα διαβάζονται όταν η απόφαση τα χρειάζεται: με πολλά
      // εμπλεκόμενα πρόσωπα, ή με μοναδικό πρόσωπο χωρίς δικό του
      // αναγνωριστικό — ο μοναδικός καλών με δικό του κερδίζει χωρίς λίστα.
      final departments =
          <({String departmentName, List<LansweeperAccount> accounts})>[];
      final needDepartments =
          partyCount > 1 ||
          !(callers.length == 1 && callers.first.hasUsername);
      if (needDepartments) {
        final seenDepartments = <int>{};
        final lookup = LookupService.instance;
        for (final call in calls) {
          final department = lookup.findDepartmentByName(
            call.departmentText ?? '',
          );
          final departmentId = department?.id;
          if (department == null || departmentId == null) continue;
          if (!seenDepartments.add(departmentId)) continue;
          final accounts = decodeLansweeperAccounts(
            department.lansweeperUsernames,
          );
          if (accounts.isEmpty) continue;
          departments.add((
            departmentName: department.name,
            accounts: accounts,
          ));
        }
      }

      final equipmentId = primary.equipmentId;
      String? asset;
      if (equipmentId != null) {
        final assetFields = await EquipmentRepository(
          db,
        ).getLansweeperAssetFieldsById(equipmentId);
        if (assetFields != null) {
          asset = lansweeperAssetTargetFor(
            storedAssetName: assetFields.assetName,
            equipmentCode: assetFields.code,
          )?.value;
        }
      }

      return LansweeperTicketParties(
        requester: resolveLansweeperRequester(
          callers: callers,
          hasUnidentifiedCalls: hasUnidentifiedCalls,
          departments: departments,
        ),
        asset: asset,
      );
    });
