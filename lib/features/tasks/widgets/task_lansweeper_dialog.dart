import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/calls_lansweeper_repository.dart';
import '../../../core/database/calls_repository.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/tasks_lansweeper_repository.dart';
import '../../../core/database/tasks_repository.dart';
import '../../../core/services/ai_ticket_suggestion_service.dart';
import '../../../core/services/lansweeper_asset_resolution.dart';
import '../../../core/services/lansweeper_department_accounts.dart';
import '../../../core/services/lansweeper_identity_diagnosis.dart';
import '../../../core/services/lansweeper_link_crosscheck.dart';
import '../../../core/services/lansweeper_party_requester_resolution.dart';
import '../../../core/services/lansweeper_sync_service.dart';
import '../../../core/services/lansweeper_requester_resolution.dart';
import '../../../core/services/lookup_service.dart';
import '../../../core/database/equipment_repository.dart';
import '../../../core/database/user_repository.dart';
import '../../../core/widgets/dialog_snackbar_scope.dart';
import '../../../core/widgets/draggable_dialog_shell.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../../history/providers/ai_ticket_suggestion_provider.dart';
import '../../history/providers/gemini_settings_provider.dart';
import '../../history/providers/lansweeper_connection_probe_provider.dart';
import '../../history/providers/lansweeper_settings_provider.dart';
import '../../history/providers/lansweeper_submit_progress_provider.dart';
import '../../history/providers/lansweeper_ticket_submit_config_provider.dart';
import '../../history/models/lansweeper_connection_status.dart';
import '../../history/widgets/lansweeper/lansweeper_browser_launcher.dart';
import '../../history/widgets/lansweeper/lansweeper_link_choice_dialog.dart';
import '../../history/widgets/lansweeper/lansweeper_submit_status.dart';
import '../../history/widgets/lansweeper/lansweeper_sync_form.dart';
import '../../history/widgets/lansweeper/lansweeper_url_rules.dart';
import '../../calls/models/call_model.dart';
import '../../calls/models/call_refined_source.dart';
import '../models/task.dart';
import '../providers/task_lansweeper_submit_provider.dart';
import '../services/task_lansweeper_form_seed.dart';

/// Ανοίγει το παράθυρο αποστολής για την [task].
///
/// Επιστρέφει `true` όταν το αίτημα δημιουργήθηκε, ώστε η κάρτα που το κάλεσε
/// να ξέρει αν αξίζει να ανανεωθεί.
Future<bool> showTaskLansweeperDialog(
  BuildContext context, {
  required Task task,
}) async {
  final result = await showDialog<bool>(
    context: context,
    // Η φόρμα κρατά κείμενο που ο χρήστης δούλεψε —και ίσως πέρασε από ΤΝ—
    // οπότε δεν κλείνει με κατά λάθος κλικ έξω από το παράθυρο.
    barrierDismissible: false,
    builder: (context) => TaskLansweeperDialog(task: task),
  );
  return result ?? false;
}

/// Το παράθυρο «Αίτημα στο Lansweeper» για μία εκκρεμότητα.
///
/// Λιτό και μονόστηλο, στο ύφος της Γρήγορης Καταγραφής: δεν υπάρχει ουρά να
/// διαλέξει κανείς, μόνο **μία** εκκρεμότητα και **μία** ενέργεια. Γι' αυτό δεν
/// φιλοξενείται μέσα στον διάλογο της Αναφοράς — εκείνος είναι φτιαγμένος γύρω
/// από τη λίστα των εκκρεμών κλήσεων, και μια δεύτερη πηγή μέσα του θα τον
/// έκανε δυσανάγνωστο και για τις δύο.
class TaskLansweeperDialog extends ConsumerStatefulWidget {
  const TaskLansweeperDialog({required this.task, super.key});

  final Task task;

  @override
  ConsumerState<TaskLansweeperDialog> createState() =>
      _TaskLansweeperDialogState();
}

class _TaskLansweeperDialogState extends ConsumerState<TaskLansweeperDialog>
    with DialogSnackbarHost {
  final SpellCheckController titleController = SpellCheckController();
  final SpellCheckController notesController = SpellCheckController();
  final SpellCheckController solutionController = SpellCheckController();

  final Map<String, String> customFieldValues = <String, String>{};
  String? selectedTicketState;
  String? selectedRequesterUsername;

  /// Ποιος και τι θα σταλεί — υπολογίζεται μία φορά, όχι σε κάθε build.
  LansweeperRequesterOptions? requesterOptions;
  String? autoAssetName;
  bool partiesLoaded = false;

  /// Η κλήση που γέννησε την εκκρεμότητα· `null` όταν δεν υπάρχει δεσμός ή δεν
  /// έχει φορτώσει ακόμη. Κρατιέται για το «Αποθήκευση στην κλήση», που πρέπει
  /// να ξέρει τι γράφει ήδη εκεί πριν υποσχεθεί αλλαγή.
  CallModel? linkedCall;

  bool aiRunning = false;
  String? aiCurrentModel;
  http.Client? aiClient;

  /// Πόση ώρα τρέχει η τρέχουσα προσπάθεια της ΤΝ.
  ///
  /// Το ρολόι ζει εδώ και όχι μέσα στη φόρμα: η φόρμα ξέρει μόνο να δείξει τον
  /// αριθμό με το σωστό χρώμα (πράσινο, πορτοκαλί στα 7 δευτερόλεπτα, κόκκινο
  /// στα 19, όπου πλησιάζει το όριο των 30). Ο χρόνος μετρά επειδή η αναμονή
  /// είναι αθέατη: χωρίς αριθμό, δέκα δευτερόλεπτα και σαράντα μοιάζουν ίδια.
  final Stopwatch aiStopwatch = Stopwatch();
  Timer? aiTicker;
  double? aiElapsedSeconds;

  /// Η εκκρεμότητα όπως τη βλέπει το παράθυρο· ανανεώνεται μετά από αποστολή,
  /// ώστε το σήμα κατάστασης να λέει την αλήθεια χωρίς να κλείσει το παράθυρο.
  late Task task = widget.task;

  @override
  void initState() {
    super.initState();
    final seed = seedLansweeperFormFromTask(task);
    titleController.text = seed.title;
    notesController.text = seed.problem;
    solutionController.text = seed.solution;
    unawaited(_loadParties());
    unawaited(_loadLinkedCall());
  }

  @override
  void dispose() {
    aiTicker?.cancel();
    aiClient?.close();
    titleController.dispose();
    notesController.dispose();
    solutionController.dispose();
    super.dispose();
  }

  /// Ποιος μπαίνει αιτών και ποιος εξοπλισμός συνδέεται.
  ///
  /// Η **ίδια** ιεραρχία που θα τρέξει και στην αποστολή: η προεπισκόπηση δεν
  /// επιτρέπεται να υπόσχεται άλλον αιτούντα από αυτόν που τελικά φεύγει.
  Future<void> _loadParties() async {
    final db = await DatabaseHelper.instance.database;
    final options = await resolveLansweeperRequesterForParties(
      userRepository: UserRepository(db),
      lookup: LookupService.instance,
      parties: [requesterPartyForTask(task)],
    );
    final asset = await resolveLansweeperAssetTarget(
      repository: EquipmentRepository(db),
      equipmentId: task.equipmentId,
      equipmentText: task.equipmentText,
    );
    if (!mounted) return;
    setState(() {
      requesterOptions = options;
      autoAssetName = asset?.value;
      partiesLoaded = true;
    });
  }

  String get _effectiveRequester =>
      selectedRequesterUsername ?? requesterOptions?.selectedUsername ?? '';

  Future<void> _suggestWithAi() async {
    if (aiRunning) return;
    final service = ref.read(aiTicketSuggestionServiceProvider);
    final configError = service.validateConfiguration();
    if (configError != null) {
      _announce(configError);
      return;
    }

    setState(() {
      aiRunning = true;
      aiElapsedSeconds = 0;
    });
    final client = http.Client();
    aiClient = client;
    try {
      final result = await service.suggest(
        AiTicketSuggestionRequest(
          callerText: (task.userText ?? '').trim(),
          equipmentText: (task.equipmentText ?? '').trim(),
          departmentText: (task.departmentText ?? '').trim(),
          // Η εκκρεμότητα δεν έχει κατηγορία προβλήματος όπως η κλήση· η
          // προτροπή δουλεύει χωρίς αυτήν, με κενό πεδίο αντί για επινοημένη
          // τιμή.
          category: '',
          issue: (task.description ?? '').trim(),
          titleText: titleController.text,
          notesText: notesController.text,
          solutionText: solutionController.text,
        ),
        client: client,
        // Κάθε απόπειρα μηδενίζει το ρολόι: όταν το κύριο μοντέλο πέσει και η
        // ροή συνεχίσει στο εφεδρικό, ο χρόνος που βλέπει ο χρήστης είναι του
        // μοντέλου που τρέχει τώρα — όχι το άθροισμα δύο αναμονών.
        onModelAttempt: (model) {
          if (!mounted) return;
          setState(() => aiCurrentModel = model);
          _startAiTicker();
        },
      );
      if (!mounted) return;
      setState(() {
        titleController.text = result.title;
        notesController.text = result.description;
        solutionController.text = result.solution;
      });
    } on AiSuggestionException catch (e) {
      _announce(e.message);
    } catch (e) {
      _announce('Η πρόταση ΤΝ απέτυχε: $e');
    } finally {
      client.close();
      _stopAiTicker();
      if (mounted) {
        setState(() {
          aiRunning = false;
          aiCurrentModel = null;
          aiElapsedSeconds = null;
        });
      }
      aiClient = null;
    }
  }

  /// Ξεκινά —ή ξαναξεκινά— το ρολόι της τρέχουσας απόπειρας.
  void _startAiTicker() {
    _stopAiTicker();
    aiStopwatch
      ..reset()
      ..start();
    aiElapsedSeconds = 0;
    aiTicker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted) return;
      setState(() => aiElapsedSeconds = aiStopwatch.elapsedMilliseconds / 1000);
    });
  }

  void _stopAiTicker() {
    aiTicker?.cancel();
    aiTicker = null;
    aiStopwatch.stop();
  }

  /// Γιατί δεν μπορεί να σωθεί το κείμενο τώρα· `null` σημαίνει «μπορεί».
  String? _saveToTaskDisabledReason() {
    if (!TasksLansweeperRepository.wouldChangeTexts(
      title: titleController.text,
      problem: notesController.text,
      solution: solutionController.text,
      current: task,
    )) {
      return 'Το κείμενο είναι ήδη αποθηκευμένο — δεν υπάρχει καμία αλλαγή.';
    }
    return null;
  }

  Future<void> _saveToTask() async {
    final db = await DatabaseHelper.instance.database;
    final saved = await TasksLansweeperRepository(db).saveTexts(
      taskId: task.id!,
      title: titleController.text,
      problem: notesController.text,
      solution: solutionController.text,
    );
    if (!mounted) return;
    if (saved) await _reloadTask();
    if (!mounted) return;
    _announce(
      saved
          ? 'Το κείμενο αποθηκεύτηκε στην εκκρεμότητα.'
          : 'Δεν υπήρχε αλλαγή να αποθηκευτεί.',
    );
  }

  /// Το κείμενο που θα γραφτεί ως Περιγραφή της κλήσης.
  ///
  /// Ο τίτλος που θα κρατήσει η συνδεδεμένη κλήση· `null` όταν δεν υπάρχει.
  ///
  /// Ο «αυτόματος τίτλος» είναι κενός εδώ: ό,τι γράφει η φόρμα μιας
  /// εκκρεμότητας είναι πάντα δικός της τίτλος, ποτέ μηχανικός.
  String? _callTitleText() => LansweeperSyncService.callTitleToPersist(
    title: titleController.text,
    autoTitle: '',
  );

  String? _saveToCallDisabledReason() {
    final call = linkedCall;
    if (call == null) return 'Η συνδεδεμένη κλήση δεν βρέθηκε.';
    if (!CallsLansweeperRepository.wouldChangeTexts(
      problem: notesController.text,
      solution: solutionController.text,
      title: _callTitleText(),
      currentIssue: call.issue,
      currentSolution: call.solution,
      currentTitle: call.title,
    )) {
      return 'Το κείμενο είναι ήδη αποθηκευμένο στην κλήση — καμία αλλαγή.';
    }
    return null;
  }

  Future<void> _saveToCall() async {
    final callId = task.callId;
    if (callId == null) return;
    final db = await DatabaseHelper.instance.database;
    await CallsLansweeperRepository(db).saveRefinedTexts(
      callIds: <int>[callId],
      problem: notesController.text,
      solution: solutionController.text,
      title: _callTitleText(),
      source: CallRefinedSource.manual,
    );
    if (!mounted) return;
    await _loadLinkedCall();
    if (!mounted) return;
    _announce('Το κείμενο αποθηκεύτηκε στην κλήση #$callId.');
  }

  Future<void> _loadLinkedCall() async {
    final callId = task.callId;
    if (callId == null) return;
    final db = await DatabaseHelper.instance.database;
    final call = await CallsRepository(db).getCallById(callId);
    if (!mounted) return;
    setState(() => linkedCall = call);
  }

  Future<void> _reloadTask() async {
    final fresh = await TasksRepository().getTaskById(task.id!);
    if (!mounted || fresh == null) return;
    setState(() => task = fresh);
  }

  /// Ρωτά όταν η κλήση που γέννησε την εκκρεμότητα έχει ήδη αίτημα.
  ///
  /// Επιστρέφει τον αριθμό του αιτήματος στο οποίο θα προσγραφεί η δουλειά,
  /// κενό για νέο ξεχωριστό αίτημα, ή `null` όταν η αποστολή ακυρώθηκε.
  Future<String?> _resolveLinkBeforeSubmit() async {
    final db = await DatabaseHelper.instance.database;
    final finding = await LansweeperLinkCrosscheck(
      calls: CallsLansweeperRepository(db),
      tasks: TasksLansweeperRepository(db),
    ).forTask(linkedCallId: task.callId);
    if (finding == null) return '';
    if (!mounted) return null;

    final viewUrlTemplate = ref.read(lansweeperTicketViewUrlProvider);
    final canOpen =
        LansweeperUrlRules.buildTicketViewUrl(
          viewUrlTemplate,
          finding.ticketId,
        ) !=
        null;
    final choice = await showLansweeperLinkChoiceDialog(
      context,
      finding: finding,
      canOpenInBrowser: canOpen,
    );
    if (!mounted) return null;

    switch (choice) {
      case null:
      case LansweeperLinkChoice.cancel:
        return null;
      case LansweeperLinkChoice.openExisting:
        await _openTicketInBrowser(finding.ticketId);
        // Το άνοιγμα ΔΕΝ στέλνει: ο χρήστης πήγε να δει τι υπάρχει ήδη.
        return null;
      case LansweeperLinkChoice.attachToExisting:
        return finding.ticketId;
      case LansweeperLinkChoice.createNew:
        return '';
    }
  }

  Future<void> _openTicketInBrowser(String ticketId) async {
    final url = LansweeperUrlRules.buildTicketViewUrl(
      ref.read(lansweeperTicketViewUrlProvider),
      ticketId,
    );
    if (url == null) {
      _announce('Ορίστε έγκυρο URL προβολής ticket στις ρυθμίσεις Lansweeper.');
      return;
    }
    final result = await LansweeperBrowserLauncher(
      launch: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    ).launchTarget(url);
    if (!mounted || result.opened) return;
    _announce('Αποτυχία ανοίγματος ticket στον περιηγητή.');
  }

  Future<void> _submit() async {
    final attachTo = await _resolveLinkBeforeSubmit();
    if (attachTo == null || !mounted) return;

    final config = ref.read(lansweeperTicketSubmitConfigProvider);
    final result = await ref
        .read(taskLansweeperSubmitProvider.notifier)
        .submitTask(
          taskId: task.id!,
          input: TaskLansweeperSubmitInput(
            title: titleController.text,
            problem: notesController.text,
            solution: solutionController.text,
            agentUsername: ref.read(lansweeperAgentUsernameProvider),
            customFieldValues: customFieldValues,
            targetTicketState: selectedTicketState ?? config.defaultTicketState,
            config: config,
            // Ό,τι δείχνει ο επιλογέας — και όταν ο χρήστης δεν τον άγγιξε,
            // ό,τι έδειξε η προεπισκόπηση. Χωρίς αυτό, η φόρμα θα υποσχόταν
            // έναν αιτούντα και θα έφευγε άλλος.
            requesterUsername: _effectiveRequester,
            attachToTicketId: attachTo.isEmpty ? null : attachTo,
          ),
        );
    if (!mounted) return;
    await _reloadTask();
    if (!mounted) return;
    _announce(result.message);
    if (result.success && mounted) Navigator.of(context).pop(true);
  }

  void _announce(String message) {
    showDialogSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(lansweeperConnectionProbeProvider);
    final config = ref.watch(lansweeperTicketSubmitConfigProvider);
    final apiUrl = ref.watch(lansweeperApiUrlProvider);
    final geminiKeyReady = ref.watch(geminiApiKeyProvider).trim().isNotEmpty;
    final submitting = ref.watch(
      lansweeperSubmitProgressProvider.select((p) => p.isRunning),
    );
    final connectionReady = connectionStatus is LansweeperConnectionAvailable;
    final canSubmit =
        !submitting &&
        connectionReady &&
        LansweeperUrlRules.isApiEndpointUrl(apiUrl);

    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: DraggableDialogShell(
        title: const Text('Αίτημα στο Lansweeper'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LansweeperSyncForm(
                    titleController: titleController,
                    notesController: notesController,
                    solutionController: solutionController,
                    autoParties: partiesLoaded
                        ? (
                            requester: _effectiveRequester.isEmpty
                                ? null
                                : _effectiveRequester,
                            asset: autoAssetName,
                          )
                        : null,
                    requesterCandidates: requesterOptions?.isChoosable ?? false
                        ? requesterOptions!.candidates
                        : const [],
                    selectedRequesterUsername: _effectiveRequester,
                    referenceDomain: _referenceDomain(),
                    onRequesterChanged: (value) =>
                        setState(() => selectedRequesterUsername = value),
                    config: config,
                    customFieldValues: customFieldValues,
                    onCustomFieldChanged: (id, value) =>
                        setState(() => customFieldValues[id] = value),
                    ticketState:
                        selectedTicketState ?? config.defaultTicketState,
                    onTicketStateChanged: (value) =>
                        setState(() => selectedTicketState = value),
                    isSuggesting: aiRunning,
                    suggestModelLabel: aiRunning ? aiCurrentModel : null,
                    suggestElapsedSeconds: aiRunning ? aiElapsedSeconds : null,
                    suggestDisabledTooltip: geminiKeyReady
                        ? null
                        : 'Λείπει το κλειδί Gemini από τις ρυθμίσεις.',
                    onSuggest: geminiKeyReady && !aiRunning
                        ? () => unawaited(_suggestWithAi())
                        : null,
                    textSaveTargets: [
                      LansweeperTextSaveTarget(
                        label: 'Αποθήκευση στην εκκρεμότητα',
                        message:
                            'Γράφει το κείμενο πάνω στην εκκρεμότητα, χωρίς '
                            'να δημιουργήσει αίτημα',
                        disabledReason: _saveToTaskDisabledReason,
                        onSave: () => unawaited(_saveToTask()),
                      ),
                      // Δεύτερος προορισμός μόνο όταν υπάρχει πού να πάει: η
                      // εκκρεμότητα που γεννήθηκε από κλήση μπορεί να θέλει το
                      // δουλεμένο κείμενο και στις δύο. Πάντα με ρητό πάτημα.
                      if (task.callId != null)
                        LansweeperTextSaveTarget(
                          label: 'Αποθήκευση στην κλήση',
                          message:
                              'Γράφει το κείμενο και πάνω στην κλήση #'
                              '${task.callId}, χωρίς να δημιουργήσει αίτημα',
                          disabledReason: _saveToCallDisabledReason,
                          onSave: () => unawaited(_saveToCall()),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LansweeperSubmitStatusBar(selectedTaskId: task.id),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton.icon(
              onPressed: canSubmit ? () => unawaited(_submit()) : null,
              icon: const Icon(Icons.cloud_upload_rounded),
              label: Text(submitting ? 'Αποστολή…' : 'Αποστολή'),
            ),
          ],
        ),
      ),
    );
  }

  /// Μέτρο σύγκρισης για τις υποψίες λάθος τομέα στον αιτούντα — ο ίδιος
  /// κανόνας με την Αναφορά.
  String? _referenceDomain() => lansweeperReferenceDomain(
    agent: LansweeperAgentIdentity.read(
      ref.read(lansweeperAgentUsernameProvider),
    ),
    knownIdentities: [
      for (final user in LookupService.instance.users)
        user.lansweeperUsername ?? '',
      for (final department in LookupService.instance.departments)
        ...decodeLansweeperAccounts(
          department.lansweeperUsernames,
        ).map((account) => account.username),
    ],
  );
}
