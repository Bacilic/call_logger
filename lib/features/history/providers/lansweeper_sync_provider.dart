import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/calls_lansweeper_repository.dart';
import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/providers/active_critical_operations_provider.dart';
import '../../../core/services/lansweeper_call_asset_resolution.dart';
import '../../../core/services/lansweeper_call_requester_resolution.dart';
import '../../../core/services/lansweeper_requester_resolution.dart';
import '../../../core/services/lansweeper_sync_service.dart';
import '../../../core/services/lansweeper_ticket_submit_config.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../calls/models/call_model.dart';
import '../../calls/provider/call_mutation_refresh.dart';
import '../models/lansweeper_sync_state.dart';
import '../services/lansweeper_registration_conflict.dart';
import '../services/lansweeper_write_failure.dart';

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
    this.ticketCreated = false,
    this.ignored = false,
    this.failureReport,
    this.warnings = const <String>[],
    this.completedSteps = const <String>[],
    this.failedStep,
  });

  final bool success;
  final String message;
  final String? ticketId;

  /// `true` όταν το αίτημα άνοιξε **τώρα**, από αυτή την αποστολή.
  ///
  /// `false` σημαίνει ότι ενημερώθηκε αίτημα που υπήρχε ήδη — το άνοιξε
  /// συνάδελφος ή προηγούμενη αποστολή μας. Το μήνυμα επιτυχίας το λέει, ώστε
  /// να μη νομίζει κανείς ότι δούλεψε σε δικό του αίτημα ενώ πάτησε πάνω σε ξένο.
  final bool ticketCreated;
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

  /// Δημοσιεύει την κατάσταση χωρίς ποτέ να πετάξει.
  ///
  /// Οι εγγραφές τελειώνουν μετά από await· αν στο μεταξύ ο provider έχει
  /// πάψει να υπάρχει, η ανάθεση κατάστασης θα έσκαγε — και μαζί της το
  /// `catch` που υποτίθεται ότι κρατά τα σφάλματα. Ένα μήνυμα που δεν
  /// προλαβαίνει να ακουστεί απλώς χάνεται· δεν ρίχνει τη ροή.
  void _publish(AsyncValue<void> next) {
    if (!ref.mounted) return;
    state = next;
  }

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
    _publish(const AsyncLoading());
    try {
      final db = await DatabaseHelper.instance.database;
      final repo = CallsRepository(db);
      final call = await repo.getCallById(callId);
      if (call == null) {
        _publish(const AsyncData(null));
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
        _publish(const AsyncData(null));
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
        // Ο χρήστης δεν άγγιξε τον επιλογέα: ισχύει η ΙΔΙΑ ιεραρχία που έδειξε
        // η φόρμα — προσωπικό αναγνωριστικό του καλούντα, αλλιώς λογαριασμός
        // του τμήματός του. Χωρίς αυτό, κλήση «Άγνωστου» έφευγε χωρίς αιτούντα
        // ενώ η γραμμή «Στο ticket» υποσχόταν τον λογαριασμό του τμήματος.
        final companions = <CallModel>[call];
        for (final id in companionCallIds) {
          if (id == callId) continue;
          final companion = await repo.getCallById(id);
          if (companion != null) companions.add(companion);
        }
        final resolved = await resolveLansweeperRequesterForCalls(
          userRepository: UserRepository(db),
          lookup: LookupService.instance,
          calls: companions,
        );
        requesterUsername = resolved.selectedUsername;
      }
      final assetTarget = await resolveCallLansweeperAsset(
        repository: EquipmentRepository(db),
        equipmentId: call.equipmentId,
        equipmentText: call.equipmentText,
      );

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
        _publish(const AsyncData(null));
        _refreshAfterLansweeperMutation();
        return LansweeperCommandResult(
          success: true,
          message: result.message,
          ticketId: result.ticketId,
          ticketCreated: result.ticketCreated,
          warnings: result.warnings,
          completedSteps: result.completedSteps,
        );
      }

      await writeRepo.updateLansweeperState(
        callId: callId,
        state: LansweeperSyncState.failed,
        // Καταγραφή της δικής μου αποτυχίας, όχι χειροκίνητη σήμανση: πρέπει
        // να γραφτεί ό,τι κι αν έκανε στο μεταξύ ο συνάδελφος, αλλιώς η κλήση
        // μένει να δείχνει «σε εξέλιξη» για μια αποστολή που έχει ήδη πέσει.
        expected: null,
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
      _publish(const AsyncData(null));
      _refreshAfterLansweeperMutation();
      return LansweeperCommandResult(
        success: false,
        message: result.message,
        ticketId: result.ticketId,
        ticketCreated: result.ticketCreated,
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
      _publish(const AsyncData(null));
      return LansweeperCommandResult(success: false, message: e.message);
    } catch (e, st) {
      _publish(AsyncError(e, st));
      final db = await DatabaseHelper.instance.database;
      await CallsLansweeperRepository(db).updateLansweeperState(
        callId: callId,
        state: LansweeperSyncState.failed,
        // Ίδιος λόγος με παραπάνω: η αποτυχία της αποστολής μου καταγράφεται
        // πάντα — δεν υπάρχει αφετηρία να συγκριθεί ούτε λόγος να μπλοκάρει.
        expected: null,
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

  /// Εξαίρεση κλήσης από το Lansweeper. `true` όταν γράφτηκε πράγματι.
  ///
  /// Η αποτυχία **πετιέται** ως [LansweeperWriteFailure] — δεν επιστρέφεται
  /// ως `false`, ώστε να μη χαθεί η αιτία της.
  Future<bool> setExcluded(
    int callId, {
    required LansweeperRegistrationBaseline? expected,
    bool force = false,
  }) => _setState(
    callId,
    LansweeperSyncState.excluded,
    expected: expected,
    force: force,
  );

  /// Επαναφορά κλήσης σε ακαταχώρητη. `true` όταν γράφτηκε πράγματι· η
  /// αποτυχία πετιέται ως [LansweeperWriteFailure], με την αιτία της.
  ///
  /// Με [retainTicketId] `false` **σβήνει** τον αριθμό αιτήματος — γι' αυτό το
  /// [expected] μετράει εδώ όσο και στη σήμανση: πάνω σε μπαγιάτικη εικόνα η
  /// ερώτηση «να κρατηθεί το αίτημα;» δεν εμφανίζεται καν, γιατί η οθόνη μου
  /// δεν ξέρει ότι υπάρχει αίτημα.
  Future<bool> setUnsent(
    int callId, {
    required LansweeperRegistrationBaseline? expected,
    bool retainTicketId = false,
    bool force = false,
  }) async {
    await _write(callId, (repo) async {
      await repo.updateLansweeperState(
        callId: callId,
        state: LansweeperSyncState.unsent,
        clearTicketId: !retainTicketId,
        expected: expected,
        force: force,
      );
    });
    _refreshAfterLansweeperMutation();
    return true;
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

  /// Το πιο πρόσφατο υπαρκτό ticket id, για δοκιμή του συνδέσμου προβολής.
  ///
  /// Το μεγαλύτερο αριθμητικό είναι και το τελευταίο που καταχωρήθηκε, άρα το
  /// πιο σίγουρα υπαρκτό στο Lansweeper. `null` όταν η βάση δεν έχει κανένα.
  Future<String?> latestLansweeperTicketId() async {
    final db = await DatabaseHelper.instance.database;
    final maxId = await CallsLansweeperRepository(
      db,
    ).maxNumericLansweeperTicketId();
    return maxId?.toString();
  }

  /// Χειροκίνητη καταχώρηση· το ticket id είναι προαιρετικό.
  ///
  /// Επιστρέφει `true` μόνο όταν η σήμανση όντως γράφτηκε — ο καλών δεν
  /// επιτρέπεται να ανακοινώσει επιτυχία για κάτι που δεν έγινε.
  ///
  /// Το `false` σημαίνει ένα μόνο πράγμα: **δεν έτρεξε καν**, επειδή υπάρχει
  /// ήδη ενεργή αποστολή. Κάθε άλλη αποτυχία πετιέται ως
  /// [LansweeperWriteFailure] και κουβαλά την αιτία της.
  Future<bool> markRegistered({
    required int callId,
    required LansweeperRegistrationBaseline? expected,
    String? ticketId,
    String? comment,
    bool force = false,
  }) async {
    if (_isRunning) return false;
    _isRunning = true;
    _publish(const AsyncLoading());
    try {
      final normalized = ticketId?.trim() ?? '';
      await _write(callId, (repo) async {
        if (normalized.isEmpty) {
          await repo.updateLansweeperState(
            callId: callId,
            state: LansweeperSyncState.sent,
            expected: expected,
            force: force,
          );
        } else {
          await repo.markManualPassed(
            callId: callId,
            ticketId: normalized,
            expected: expected,
            force: force,
            comment: comment,
          );
        }
      });
      _refreshAfterLansweeperMutation();
      return true;
    } finally {
      _isRunning = false;
    }
  }

  Future<bool> _setState(
    int callId,
    String nextState, {
    required LansweeperRegistrationBaseline? expected,
    bool force = false,
  }) async {
    await _write(callId, (repo) async {
      await repo.updateLansweeperState(
        callId: callId,
        state: nextState,
        expected: expected,
        force: force,
      );
    });
    _refreshAfterLansweeperMutation();
    return true;
  }

  /// Εκτελεί μια εγγραφή κατάστασης και φροντίζει τι φτάνει στην οθόνη.
  ///
  /// Η διένεξη **ξαναπετιέται**, ντυμένη με το «ποιος και πότε» — αλλιώς ο
  /// διάλογος που ρωτά τον άνθρωπο δεν θα εμφανιζόταν ποτέ. Η ταυτότητα
  /// ζητείται εδώ, ώστε καμία οθόνη να μη χρειάζεται να θυμηθεί να τη ζητήσει.
  ///
  /// Κάθε άλλη αποτυχία **πετιέται** ως [LansweeperWriteFailure], με την αιτία
  /// ντυμένη σε ανθρώπινα ελληνικά και μια τεχνική αναφορά προς αντιγραφή. Όσο
  /// γύριζε σκέτο `false`, η αιτία έμενε μόνο στην κατάσταση του provider — που
  /// καμία οθόνη δεν διαβάζει για σφάλματα, παρά μόνο για το «φορτώνει;».
  ///
  /// Το άνοιγμα της βάσης γίνεται **μέσα** στο `try`: αλλιώς μια αποτυχία
  /// εκεί αφήνει πίσω της το `AsyncLoading` που έβαλε ο καλών, και η
  /// Αναφορά κρατά τα κουμπιά της κλειδωμένα για μια δουλειά που έχει ήδη
  /// πέσει.
  Future<void> _write(
    int callId,
    Future<void> Function(CallsLansweeperRepository repo) write,
  ) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await write(CallsLansweeperRepository(db));
      _publish(const AsyncData(null));
    } on LansweeperRegistrationStaleException catch (stale) {
      _publish(const AsyncData(null));
      final db = await DatabaseHelper.instance.database;
      final actor = await CallsRepository(db).lastActorFor(callId);
      throw LansweeperRegistrationStaleException(
        stale.conflict.describedBy(who: actor.who, at: actor.at),
      );
    } catch (e, st) {
      // Η κατάσταση εξακολουθεί να δημοσιεύεται (τα κουμπιά ξεκλειδώνουν)· η
      // αιτία όμως δεν μένει ΜΟΝΟ εκεί, γιατί εκεί δεν τη βλέπει κανείς.
      _publish(AsyncError(e, st));
      throw LansweeperWriteFailure(
        message: humanizeUserFacingError(e),
        report: _buildWriteFailureReport(callId: callId, error: e, stack: st),
      );
    }
  }

  /// Η τεχνική αναφορά μιας αποτυχημένης εγγραφής, στο ύφος της αποτυχίας API.
  String _buildWriteFailureReport({
    required int callId,
    required Object error,
    required StackTrace stack,
  }) {
    return <String>[
      'Lansweeper write failed',
      'callId: $callId',
      'error: $error',
      'timestamp: ${DateTime.now().toIso8601String()}',
      '',
      'stack:',
      '$stack',
    ].join('\n');
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

/// Ζει όσο η εφαρμογή, όχι όσο η οθόνη που τον κάλεσε.
///
/// Το μενού κατάστασης του Ιστορικού τον διαβάζει μια στιγμή και του δίνει τη
/// δουλειά, χωρίς καμία οθόνη να τον παρακολουθεί. Όσο ήταν `autoDispose`,
/// πέθαινε στο πρώτο await και η εγγραφή τέλειωνε πάνω σε νεκρό `Ref` — ενώ η
/// Αναφορά δεν το έβλεπε ποτέ, επειδή ο διάλογός της τον κρατά τυχαία ζωντανό.
/// Εδώ ζει και το `_isRunning`: σε βραχύβιο instance η προστασία από διπλή
/// αποστολή μηδενιζόταν σε κάθε ενέργεια.
final lansweeperSyncProvider =
    AsyncNotifierProvider<LansweeperSyncNotifier, void>(
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

      final asset = (await resolveCallLansweeperAsset(
        repository: EquipmentRepository(db),
        equipmentId: primary.equipmentId,
        equipmentText: primary.equipmentText,
      ))?.value;

      return LansweeperTicketParties(
        requester: await resolveLansweeperRequesterForCalls(
          userRepository: UserRepository(db),
          lookup: LookupService.instance,
          calls: calls,
        ),
        asset: asset,
      );
    });
