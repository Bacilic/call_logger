import '../../../core/widgets/dialog_snackbar_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/audit_service.dart';
import '../../../core/services/save_confirmation_summary.dart';
import '../../../core/utils/call_duration_format.dart';
import '../../../core/utils/history_entity_display_utils.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import '../../../core/widgets/resizable_text_area.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../../calls/models/call_model.dart';
import '../../calls/models/call_refined_source.dart';
import '../../calls/provider/smart_entity_selector_provider.dart';
import '../../calls/screens/widgets/smart_entity_selector_widget.dart';
import '../../tasks/models/task.dart';
import '../../tasks/providers/task_service_provider.dart';
import '../providers/history_call_actions_provider.dart';
import 'call_provenance_icon.dart';
import 'linked_task_details_dialog.dart';
import 'linked_tasks_card.dart';
import '../providers/history_provider.dart';
import '../providers/lansweeper_settings_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import '../services/lansweeper_submission_warnings.dart';
import 'lansweeper/lansweeper_edit_warning.dart';

Future<void> showCallEditDialog(BuildContext context, {required int callId}) {
  return showDialog<void>(
    context: context,
    // Σημερινή συμπεριφορά, δηλωμένη: το κλικ έξω δεν κλείνει.
    barrierDismissible: false,
    builder: (context) => _CallEditDialog(callId: callId),
  );
}

class _CallEditDialog extends ConsumerStatefulWidget {
  const _CallEditDialog({required this.callId});

  final int callId;

  @override
  ConsumerState<_CallEditDialog> createState() => _CallEditDialogState();
}

class _CallEditDialogState extends ConsumerState<_CallEditDialog>
    with DialogSnackbarHost {
  late final SpellCheckController _issueController;
  late final SpellCheckController _solutionController;
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _hardCloneBusy = false;
  ProviderContainer? _providerContainer;

  CallModel? _original;
  List<Task> _linkedTasks = const <Task>[];

  /// Το ίχνος εξευγενισμού της Περιγραφής — «από ΤΝ · επεξεργασμένο · 10/08
  /// 09:38». Κενό όταν η κλήση δεν πέρασε ποτέ από τη φόρμα Lansweeper.
  String get _provenance => CallRefinedSource.provenanceLabel(
    source: _original?.refinedSource,
    refinedAt: _original?.refinedAt,
  );
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int? _categoryId;
  String _categoryText = '';

  @override
  void initState() {
    super.initState();
    _issueController = SpellCheckController();
    _solutionController = SpellCheckController();
    _load();
  }

  @override
  void dispose() {
    _issueController.dispose();
    _solutionController.dispose();
    _durationController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    final container = _providerContainer;
    if (container != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        container.invalidate(historyEditSmartEntityProvider);
      });
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _providerContainer ??= ProviderScope.containerOf(context);
  }

  Future<void> _load() async {
    final service = ref.read(historyCallActionsServiceProvider);
    final call = await service.getCallById(widget.callId);
    if (!mounted) return;
    if (call == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Η κλήση δεν βρέθηκε.')));
      return;
    }
    await ref.read(historyEditSmartEntityProvider.notifier).loadFromCall(call);
    if (!mounted) return;
    _original = call;
    _issueController.text = call.issue ?? '';
    _solutionController.text = call.solution ?? '';
    _durationController.text = call.duration?.toString() ?? '';
    _categoryId = call.categoryId;
    _categoryText = (call.category ?? '').trim();
    _selectedDate = _parseDate(call.date);
    _selectedTime = _parseTime(call.time);
    _syncDateTimeControllers();
    setState(() => _loading = false);
    await _loadLinkedTasks();
  }

  /// Οι συνδεδεμένες εκκρεμότητες φορτώνονται χωριστά, μετά την κλήση: δεν
  /// εμποδίζουν την επεξεργασία αν αργήσουν ή αποτύχουν.
  Future<void> _loadLinkedTasks() async {
    final tasks = await ref
        .read(taskServiceProvider)
        .getTasksForCall(widget.callId);
    if (!mounted) return;
    setState(() => _linkedTasks = tasks);
  }

  Future<void> _openLinkedTask(Task task) async {
    await showLinkedTaskDetailsDialog(context, task: task);
    if (!mounted) return;
    // Ο διάλογος μπορεί να άλλαξε τίτλο ή κατάσταση — ξαναδιαβάζουμε.
    await _loadLinkedTasks();
  }

  DateTime? _parseDate(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(trimmed);
    } catch (_) {
      return null;
    }
  }

  TimeOfDay? _parseTime(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _selectedDate ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    setState(() {
      _selectedDate = date;
      _syncDateTimeControllers();
    });
  }

  Future<void> _pickTime() async {
    final initial = _selectedTime ?? TimeOfDay.now();
    final time = await showTimePicker(context: context, initialTime: initial);
    if (time == null || !mounted) return;
    setState(() {
      _selectedTime = time;
      _syncDateTimeControllers();
    });
  }

  String? _dateSql() {
    final d = _selectedDate;
    if (d == null) return null;
    return DateFormat('yyyy-MM-dd').format(d);
  }

  String? _timeSql() {
    final t = _selectedTime;
    if (t == null) return null;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _syncDateTimeControllers() {
    _dateController.text = _selectedDate == null
        ? ''
        : DateFormat('dd/MM/yyyy').format(_selectedDate!);
    _timeController.text = _selectedTime == null
        ? ''
        : '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (_saving || _original == null) return;
    final durationRaw = _durationController.text.trim();
    final duration = durationRaw.isEmpty ? null : int.tryParse(durationRaw);
    if (durationRaw.isNotEmpty && duration == null) {
      showDialogSnackBar(
        const SnackBar(
          content: Text('Η διάρκεια πρέπει να είναι ακέραιος αριθμός.'),
        ),
      );
      return;
    }

    final selector = ref.read(historyEditSmartEntityProvider);
    final callerId = selector.selectedCaller?.id;
    final equipmentId = selector.selectedEquipment?.id;
    final callerTextRaw = selector.callerDisplayText.trim();
    final phoneRaw = selector.selectedPhone?.trim() ?? '';
    final departmentRaw = selector.departmentText.trim();
    final equipmentRaw = selector.equipmentText.trim();
    final issueRaw = _issueController.text.trim();
    final solutionRaw = _solutionController.text.trim();
    final categoryRaw = _categoryText.trim();

    // Το ίχνος εξευγενισμού ακολουθεί το κείμενο. Κλήση με ίχνος που
    // διορθώνεται εδώ: το «από ΤΝ» γίνεται «επεξεργασμένο» και η χρονοσφραγίδα
    // ανανεώνεται. Κλήση χωρίς ίχνος: αποκτά «χειρόγραφο» μόνο όταν γραφτεί
    // λύση — σκέτη διόρθωση της Περιγραφής είναι επεξεργασία σημειώσεων, όχι
    // εξευγενισμός, και δεν δικαιούται εικονίδιο στο Ιστορικό.
    final textChanged =
        issueRaw != (_original!.issue ?? '').trim() ||
        solutionRaw != (_original!.solution ?? '').trim();
    final hasTrace = _original!.refinedSource != null;
    String? refinedSource;
    String? refinedAt;
    if (hasTrace) {
      // Μόνο το ανέγγιχτο «από ΤΝ» προάγεται σε «επεξεργασμένο»· το χειρόγραφο
      // και το ήδη επεξεργασμένο κρατούν τον χαρακτηρισμό τους.
      refinedSource =
          textChanged && _original!.refinedSource == CallRefinedSource.ai
          ? CallRefinedSource.aiEdited
          : _original!.refinedSource;
      refinedAt = textChanged
          ? DateTime.now().toIso8601String()
          : _original!.refinedAt;
    } else if (solutionRaw.isNotEmpty) {
      refinedSource = CallRefinedSource.manual;
      refinedAt = textChanged
          ? DateTime.now().toIso8601String()
          : _original!.refinedAt;
    }

    final updated = CallModel(
      id: _original!.id,
      date: _dateSql(),
      time: _timeSql(),
      callerId: callerId,
      equipmentId: equipmentId,
      callerText: callerId != null
          ? null
          : (callerTextRaw.isEmpty ? null : callerTextRaw),
      phoneText: phoneRaw.isEmpty ? null : phoneRaw,
      departmentText: departmentRaw.isEmpty ? null : departmentRaw,
      equipmentText: equipmentRaw.isEmpty ? null : equipmentRaw,
      issue: issueRaw.isEmpty ? null : issueRaw,
      solution: solutionRaw.isEmpty ? null : solutionRaw,
      refinedSource: refinedSource,
      refinedAt: refinedAt,
      category: categoryRaw.isEmpty ? null : categoryRaw,
      categoryId: _categoryId,
      status: _original!.status,
      duration: duration,
      isPriority: _original!.isPriority,
      lansweeperState: _original!.lansweeperState,
      lansweeperMainTicketId: _original!.lansweeperMainTicketId,
      lansweeperLastSyncAt: _original!.lansweeperLastSyncAt,
      isDeleted: _original!.isDeleted,
    );

    setState(() => _saving = true);
    try {
      await ref.read(historyCallActionsServiceProvider).saveEditedCall(updated);
      if (!mounted) return;
      final saveMessage = buildSaveConfirmationMessage(
        entityType: AuditEntityTypes.call,
        entityLabel: '#${_original!.id}',
        oldMap: _original!.toMap(),
        newMap: updated.toMap(),
        isNew: false,
      );
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saveMessage),
          duration: saveConfirmationSnackBarDuration(saveMessage),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDialogSnackBar(
        SnackBar(
          content: Text(
            'Αποτυχία ενημέρωσης κλήσης: ${humanizeUserFacingError(e)}',
          ),
        ),
      );
    }
  }

  Future<void> _cloneCall() async {
    if (_hardCloneBusy) return;
    setState(() => _hardCloneBusy = true);
    try {
      final id = await ref
          .read(historyCallActionsServiceProvider)
          .cloneCall(widget.callId);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Δημιουργήθηκε κλωνοποιημένη κλήση (#$id).')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _hardCloneBusy = false);
      showDialogSnackBar(
        SnackBar(
          content: Text('Αποτυχία κλωνοποίησης: ${humanizeUserFacingError(e)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryEntriesAsync = ref.watch(historyCategoryEntriesProvider);
    final selector = ref.watch(historyEditSmartEntityProvider);
    final original = _original;
    final hasLansweeperTicket =
        (original?.lansweeperMainTicketId?.trim().isNotEmpty ?? false) ||
        original?.lansweeperState == 'sent';

    // Το watch γίνεται άνευ όρων, έξω από κάθε `if`: ένα watch που άλλοτε
    // εκτελείται και άλλοτε όχι αλλάζει το σύνολο των εξαρτήσεων του widget
    // από build σε build. Το ιστορικό είναι μια μικρή τοπική ανάγνωση και
    // δεν κοστίζει τίποτα όταν δεν χρειάζεται.
    final lansweeperWarnings = ref
        .watch(callExternalLinksProvider(widget.callId))
        .maybeWhen(
          data: (links) => lansweeperWarningsForTicket(
            links: links,
            ticketId: original?.lansweeperMainTicketId,
          ),
          orElse: () => const <String>[],
        );

    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: Center(
        child: AlertDialog(
          title: const Text('Επεξεργασία κλήσης'),
          // Το οριζόντιο περιθώριο περνά μέσα στο scrollable, ώστε η μπάρα
          // κύλησης να μένει στην άκρη του διαλόγου και όχι πάνω στα πεδία.
          contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
          content: SizedBox(
            width: 1028,
            child: _loading
                ? const SizedBox(
                    height: 280,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hasLansweeperTicket) ...[
                          LansweeperEditWarning(
                            ticketId: original?.lansweeperMainTicketId,
                            ticketViewUrlTemplate: ref.watch(
                              lansweeperTicketViewUrlProvider,
                            ),
                            onClone: _cloneCall,
                            cloneBusy: _hardCloneBusy,
                            warnings: lansweeperWarnings,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_linkedTasks.isNotEmpty) ...[
                          LinkedTasksCard(
                            tasks: _linkedTasks,
                            onOpen: _openLinkedTask,
                          ),
                          const SizedBox(height: 12),
                        ],
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const gaps = 36.0; // 3 * 12 μεταξύ πεδίων.
                            final mw = constraints.maxWidth;
                            final available = (mw - gaps).clamp(
                              200.0,
                              double.infinity,
                            );
                            final w1 = (available * 0.26).clamp(170.0, 280.0);
                            final w2 = (available * 0.32).clamp(200.0, 340.0);
                            final wDept = (available * 0.22).clamp(
                              150.0,
                              250.0,
                            );
                            final w3 = (available * 0.2).clamp(140.0, 220.0);
                            final minRowWidth =
                                w1 + 12 + w2 + 12 + wDept + 12 + w3;
                            final selector = SmartEntitySelectorWidget(
                              provider: historyEditSmartEntityProvider,
                              w1: w1,
                              w2: w2,
                              wDept: wDept,
                              w3: w3,
                              trailingRowChildren: const [],
                            );
                            if (mw + 0.5 < minRowWidth) {
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: minRowWidth,
                                  child: selector,
                                ),
                              );
                            }
                            return selector;
                          },
                        ),
                        const SizedBox(height: 12),
                        categoryEntriesAsync.when(
                          data: (entries) {
                            final options = <({int? id, String name})>[
                              (id: null, name: '— Χωρίς κατηγορία —'),
                              ...entries.map((e) => (id: e.id, name: e.name)),
                            ];
                            final selected =
                                options.any((e) => e.id == _categoryId)
                                ? _categoryId
                                : null;
                            return DropdownButtonFormField<int?>(
                              initialValue: selected,
                              decoration: const InputDecoration(
                                labelText: 'Κατηγορία',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: options
                                  .map(
                                    (entry) => DropdownMenuItem<int?>(
                                      value: entry.id,
                                      child: Text(entry.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _categoryId = value;
                                  _categoryText =
                                      entries
                                          .where((e) => e.id == value)
                                          .map((e) => e.name)
                                          .firstOrNull ??
                                      '';
                                });
                              },
                            );
                          },
                          loading: () => const SizedBox(
                            height: 44,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                readOnly: true,
                                controller: _dateController,
                                decoration: const InputDecoration(
                                  labelText: 'Ημερομηνία',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Επιλογή ημερομηνίας',
                              onPressed: _pickDate,
                              icon: const Icon(Icons.calendar_today),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                readOnly: true,
                                controller: _timeController,
                                decoration: const InputDecoration(
                                  labelText: 'Ώρα',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Επιλογή ώρας',
                              onPressed: _pickTime,
                              icon: const Icon(Icons.access_time),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _durationController,
                          builder: (context, value, _) => TextFormField(
                            controller: _durationController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: callDurationFieldLabel(value.text),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_provenance.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              CallProvenanceIcon(
                                source: _original?.refinedSource,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _provenance,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                        ResizableTextArea(
                          controller: _issueController,
                          minLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Περιγραφή κλήσης',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ResizableTextArea(
                          controller: _solutionController,
                          minLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Λύση',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (historyEntityIsDeleted(
                          selector.selectedCaller?.isDeleted,
                        ))
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                              'Ο συνδεδεμένος καλών είναι διαγραμμένος στον κατάλογο. Θα διατηρηθεί το snapshot κειμένου.',
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Ακύρωση'),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Αποθήκευση'),
            ),
          ],
        ),
      ),
    );
  }
}
