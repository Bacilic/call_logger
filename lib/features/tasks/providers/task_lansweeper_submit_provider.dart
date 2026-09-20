import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/tasks_lansweeper_repository.dart';
import '../../../core/database/tasks_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/providers/active_critical_operations_provider.dart';
import '../../../core/services/lansweeper_asset_resolution.dart';
import '../../../core/services/lansweeper_party_requester_resolution.dart';
import '../../../core/services/lansweeper_sync_service.dart';
import '../../../core/services/lansweeper_ticket_submit_config.dart';
import '../../../core/services/lookup_service.dart';
import '../../history/models/lansweeper_submit_progress.dart';
import '../../history/providers/lansweeper_submit_progress_provider.dart';
import '../../history/providers/lansweeper_sync_provider.dart';
import '../models/task.dart';
import 'tasks_provider.dart';

/// Ό,τι έδειχνε η φόρμα τη στιγμή που πατήθηκε η «Αποστολή».
class TaskLansweeperSubmitInput {
  const TaskLansweeperSubmitInput({
    required this.title,
    required this.problem,
    required this.solution,
    required this.agentUsername,
    this.customFieldValues = const <String, String>{},
    this.targetTicketState,
    this.config,
    this.requesterUsername,
    this.attachToTicketId,
  });

  final String title;
  final String problem;
  final String solution;
  final String agentUsername;
  final Map<String, String> customFieldValues;
  final String? targetTicketState;
  final LansweeperTicketSubmitConfig? config;

  /// Ο αιτών που έδειχνε η φόρμα.
  ///
  /// `null` = η φόρμα δεν είχε άποψη, οπότε αποφασίζει η αυτόματη ιεραρχία.
  /// Κενό κείμενο = ρητή επιλογή «χωρίς αιτούντα» — μπαίνει ο πράκτορας.
  final String? requesterUsername;

  /// Το αίτημα στο οποίο προσγράφεται η δουλειά, αντί να ανοίξει νέο.
  ///
  /// Γεμίζει **μόνο** όταν ο χρήστης το διάλεξε μπροστά στον δεσμό: η κλήση
  /// που γέννησε την εκκρεμότητα έχει ήδη αίτημα, και εκείνος αποφάσισε ότι
  /// πρόκειται για την ίδια δουλειά. Η ροή τότε προσθέτει σημείωση αντί να
  /// δημιουργήσει δεύτερο ticket για το ίδιο πρόβλημα.
  final String? attachToTicketId;
}

/// Η αποστολή μιας **εκκρεμότητας** στο Lansweeper.
///
/// Αδελφός του `LansweeperSyncNotifier`, όχι επέκτασή του: μοιράζονται τη ροή
/// αποστολής, την ιεραρχία του αιτούντα και τον εντοπισμό εξοπλισμού, αλλά
/// διαφέρουν σε δύο πράγματα που δεν είναι λεπτομέρειες.
///
/// 1. **Ο χρόνος δεν στέλνεται ποτέ.** Ο χρόνος μιας κλήσης είναι χρόνος
///    εργασίας· ο χρόνος μιας εκκρεμότητας είναι χρόνος **αναμονής** — μια
///    αλλαγή καλωδίου μπορεί να περιμένει τρεις μέρες για μισή ώρα δουλειάς.
///    Σταλμένος, θα έλεγε ψέματα στο helpdesk.
/// 2. **Η αποστολή δεν αγγίζει το κείμενο.** Στις κλήσεις, ό,τι φεύγει στο
///    αίτημα γράφεται και πίσω στην κλήση, γιατί εκεί το δουλεμένο κείμενο
///    είναι το καλύτερο που υπάρχει. Στην εκκρεμότητα ισχύει το αντίθετο: το
///    προσεγμένο κείμενο είναι ήδη μέσα της, γραμμένο από άνθρωπο. Η ΤΝ γράφει
///    για το helpdesk, όχι για τον χρήστη — και το κείμενό της σώζεται **μόνο**
///    με ρητό πάτημα.
class TaskLansweeperSubmitNotifier extends AsyncNotifier<void> {
  bool _isRunning = false;

  @override
  FutureOr<void> build() {}

  void _publish(AsyncValue<void> next) {
    if (!ref.mounted) return;
    state = next;
  }

  Future<LansweeperCommandResult> submitTask({
    required int taskId,
    required TaskLansweeperSubmitInput input,
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
    final progress = ref.read(lansweeperSubmitProgressProvider.notifier);
    criticalOps.begin(CriticalOperation.lansweeperTicketSubmit);
    _publish(const AsyncLoading());
    // Σφραγίζεται μία φορά, στο `finally`: όσα σημεία εξόδου κι αν προστεθούν
    // αύριο, κανένα δεν μπορεί να αφήσει την ένδειξη να τρέχει για πάντα.
    var progressSucceeded = false;
    String? progressSummary;
    try {
      final db = await DatabaseHelper.instance.database;
      final tasksRepo = TasksRepository();
      final row = await tasksRepo.getTaskRowById(taskId);
      if (row == null) {
        _publish(const AsyncData(null));
        return const LansweeperCommandResult(
          success: false,
          message: 'Δεν βρέθηκε η εκκρεμότητα για αποστολή.',
        );
      }
      final task = Task.fromMap(row);

      if (input.agentUsername.trim().isEmpty) {
        _publish(const AsyncData(null));
        return const LansweeperCommandResult(
          success: false,
          message: 'Ο πράκτορας API (AgentUsername) είναι υποχρεωτικός.',
        );
      }

      final config = input.config ?? LansweeperTicketSubmitConfig.defaults();
      // Η ρητή επιλογή του χρήστη μπροστά στον δεσμό κερδίζει: όταν αποφάσισε
      // ότι η δουλειά ανήκει στο αίτημα της κλήσης, εκείνο ενημερώνεται — και
      // η εκκρεμότητα δείχνει από εδώ και πέρα στο ίδιο.
      final attachTo = input.attachToTicketId?.trim() ?? '';
      final existingTicketIdRaw = attachTo.isNotEmpty
          ? attachTo
          : (task.lansweeperMainTicketId ?? '').trim();
      final existingTicketId = existingTicketIdRaw.isEmpty
          ? null
          : existingTicketIdRaw;
      final targetState = (input.targetTicketState?.trim().isNotEmpty ?? false)
          ? input.targetTicketState!.trim()
          : config.defaultTicketState;

      // Ό,τι έδειξε η φόρμα κερδίζει: εκεί ο χρήστης μπορεί να διάλεξε
      // λογαριασμό τμήματος ή ρητά «χωρίς αιτούντα», και η επιλογή του δεν
      // επιτρέπεται να παρακαμφθεί από την αυτόματη ιεραρχία.
      final String? requesterUsername;
      final formChoice = input.requesterUsername;
      if (formChoice != null) {
        final chosen = formChoice.trim();
        requesterUsername = chosen.isEmpty ? null : chosen;
      } else {
        final resolved = await resolveLansweeperRequesterForParties(
          userRepository: UserRepository(db),
          lookup: LookupService.instance,
          parties: [requesterPartyForTask(task)],
        );
        requesterUsername = resolved.selectedUsername;
      }

      final assetTarget = await resolveLansweeperAssetTarget(
        repository: EquipmentRepository(db),
        equipmentId: task.equipmentId,
        equipmentText: task.equipmentText,
      );

      final service = ref.read(lansweeperSyncServiceProvider);
      final request = LansweeperWorkflowRequest(
        // Η εκκρεμότητα έχει δικό της τίτλο — δεν χρειάζεται να τον εφεύρει
        // κανείς από κατηγορία και αριθμό, όπως η κλήση.
        autoSubject: task.title.trim().isEmpty
            ? 'Εκκρεμότητα #$taskId'
            : task.title.trim(),
        title: input.title,
        problem: input.problem,
        solution: input.solution,
        agentUsername: input.agentUsername,
        // Καμία διάρκεια, ποτέ — δες την τεκμηρίωση της κλάσης.
        durationSeconds: null,
        config: config,
        customFieldValues: input.customFieldValues,
        targetState: targetState,
        existingTicketId: existingTicketId,
        requesterUsername: requesterUsername,
        assetTarget: assetTarget,
      );

      progress.begin(
        <String>[
          ...LansweeperSyncService.plannedStepKeys(request),
          LansweeperSubmitStepKeys.save,
        ],
        creatingTicket: existingTicketId == null,
        taskIds: <int>[taskId],
      );
      final result = await service.submitTicketWorkflow(
        request,
        onStep: progress.stepStarted,
      );

      // ΦΡΕΣΚΟ handle βάσης μετά από μακρύ await: το `db` παραπάνω δεσμεύτηκε
      // πριν την αποστολή, και αν η βάση εναλλάχθηκε στο μεταξύ θα γράφαμε σε
      // λάθος στόχο — με το αίτημα ΗΔΗ ανοιγμένο στο Lansweeper.
      progress.stepStarted(LansweeperSubmitStepKeys.save);
      final writeRepo = TasksLansweeperRepository(
        await DatabaseHelper.instance.database,
      );

      final ticketId = result.ticketId?.trim() ?? '';
      if (result.success && ticketId.isNotEmpty) {
        await writeRepo.markSubmitted(taskId: taskId, ticketId: ticketId);
        progressSucceeded = true;
        progressSummary = 'Καταχωρήθηκε · αίτημα $ticketId';
        _publish(const AsyncData(null));
        _refreshTasks();
        return LansweeperCommandResult(
          success: true,
          message: result.message,
          ticketId: result.ticketId,
          ticketCreated: result.ticketCreated,
          warnings: result.warnings,
          completedSteps: result.completedSteps,
        );
      }

      // Ο αριθμός περνά κι εδώ όταν υπάρχει: αίτημα που γεννήθηκε και έσπασε σε
      // επόμενο βήμα δεν επιτρέπεται να μείνει ανώνυμο.
      await writeRepo.markFailed(
        taskId: taskId,
        ticketId: ticketId.isEmpty ? null : ticketId,
      );
      progressSummary = (result.failedStep ?? '').trim().isEmpty
          ? 'Αποτυχία: ${result.message}'
          : 'Αποτυχία στο ${result.failedStep}: ${result.message}';
      _publish(const AsyncData(null));
      _refreshTasks();
      return LansweeperCommandResult(
        success: false,
        message: result.message,
        ticketId: result.ticketId,
        warnings: result.warnings,
        completedSteps: result.completedSteps,
        failedStep: result.failedStep,
      );
    } on LansweeperSyncPrecheckException catch (e) {
      // Η ρύθμιση ή η είσοδος κόπηκε ΠΡΙΝ φύγει οτιδήποτε προς το Lansweeper.
      // Καμία σήμανση αποτυχίας: η εκκρεμότητα δεν δοκίμασε ποτέ.
      progressSummary = 'Αποτυχία: ${e.message}';
      _publish(const AsyncData(null));
      return LansweeperCommandResult(success: false, message: e.message);
    } catch (e, st) {
      progressSummary = 'Αποτυχία: $e';
      _publish(AsyncError(e, st));
      final freshDb = await DatabaseHelper.instance.database;
      await TasksLansweeperRepository(freshDb).markFailed(taskId: taskId);
      _refreshTasks();
      return LansweeperCommandResult(success: false, message: e.toString());
    } finally {
      progress.finish(success: progressSucceeded, summary: progressSummary);
      _isRunning = false;
      criticalOps.end(CriticalOperation.lansweeperTicketSubmit);
    }
  }

  void _refreshTasks() {
    if (!ref.mounted) return;
    ref.invalidate(tasksProvider);
  }
}

final taskLansweeperSubmitProvider =
    AsyncNotifierProvider<TaskLansweeperSubmitNotifier, void>(
      TaskLansweeperSubmitNotifier.new,
    );

/// Ποιο πρόσωπο-και-τμήμα εκπροσωπεί η [task] στην ιεραρχία του αιτούντα.
///
/// Ζει χωριστά από τη ροή αποστολής επίτηδες: την ίδια μετάφραση χρειάζεται
/// και η **προεπισκόπηση** της φόρμας, που πρέπει να δείχνει ακριβώς τον
/// αιτούντα που θα σταλεί. Γραμμένη δύο φορές, οι δύο απαντήσεις θα απέκλιναν —
/// ακριβώς το σφάλμα που είχε ήδη συμβεί στις κλήσεις.
LansweeperRequesterParty requesterPartyForTask(Task task) {
  final label = (task.userText ?? '').trim();
  return LansweeperRequesterParty(
    personId: task.callerId,
    personLabel: label.isEmpty ? 'Υπάλληλος #${task.callerId}' : label,
    departmentText: task.departmentText ?? '',
  );
}
