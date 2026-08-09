import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/compact_tooltip.dart';
import '../../../core/widgets/draggable_dialog_shell.dart';
import '../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../core/widgets/resizable_text_area.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../../calls/provider/smart_entity_selector_provider.dart';
import '../../calls/screens/widgets/smart_entity_selector_widget.dart';
import '../models/task.dart';
import '../models/task_settings_config.dart';
import '../providers/task_service_provider.dart';
import '../providers/task_settings_config_provider.dart';
import '../ui/task_due_option_tooltips.dart';
import '../ui/task_due_quick_chips.dart';
import '../utils/task_completion_summary.dart';

/// Ψευδο-κωδικός για το chip «Προεπιλογή ρυθμίσεων» — δεν αποθηκεύεται πουθενά,
/// χρησιμεύει μόνο για να ξεχωρίζει το chip μέσα στη σειρά.
const String _kSettingsDefaultOption = 'settings_default';

/// Το κανονικό οριζόντιο περιθώριο διαλόγου του Material.
const double _kDialogHorizontalPadding = 24;

/// Τι απογίνεται μια ολοκληρωμένη εκκρεμότητα με την αποθήκευση της φόρμας.
///
/// Η απόφαση επιλέγεται ΜΕΣΑ στη φόρμα και επιστρέφει μαζί με το αποτέλεσμα —
/// δεν υπάρχει προηγούμενο βήμα που η φόρμα δεν θυμάται.
enum ClosedTaskSaveMode {
  /// Μόνο διόρθωση κειμένου· η κατάσταση και η στιγμή της λύσης δεν αλλάζουν.
  stayClosed,

  /// Αναίρεση ολοκλήρωσης — η ίδια εκκρεμότητα ξαναγίνεται ανοιχτή.
  reopen,

  /// Ξανανοίγει σε αναβολή· η νέα λήξη και ο λόγος ορίζονται στην ίδια φόρμα.
  snoozeAgain,

  /// Νέα καθαρή εκκρεμότητα· η τωρινή μένει ολοκληρωμένη στο αρχείο.
  recreate,
}

/// Αποτέλεσμα της φόρμας εκκρεμότητας: τα δεδομένα + η απόφαση κατάστασης.
class TaskFormResult {
  const TaskFormResult(this.task, {this.closedMode, this.snoozeReason});

  final Task task;

  /// null όταν η φόρμα δεν αφορούσε ολοκληρωμένη εκκρεμότητα.
  final ClosedTaskSaveMode? closedMode;

  /// Ο λόγος της νέας αναβολής — μόνο για [ClosedTaskSaveMode.snoozeAgain].
  final String? snoozeReason;
}

/// Επιστρέφει το αποτέλεσμα της φόρμας ή null αν ακυρώθηκε.
Future<TaskFormResult?> showTaskFormDialog(BuildContext context, {Task? task}) {
  return showDialog<TaskFormResult>(
    context: context,
    builder: (context) => _TaskFormDialog(task: task),
  );
}

class _TaskFormDialog extends ConsumerStatefulWidget {
  const _TaskFormDialog({this.task});

  final Task? task;

  @override
  ConsumerState<_TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends ConsumerState<_TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final GlobalKey<SmartEntitySelectorWidgetState> _entitySelectorKey =
      GlobalKey<SmartEntitySelectorWidgetState>();

  /// Για ασφαλές `invalidate` στο `dispose` — το `ref` εκεί δεν επιτρέπεται.
  ProviderContainer? _providerContainer;
  late final SpellCheckController _titleController;
  late final SpellCheckController _descriptionController;
  late final List<SpellCheckController> _snoozeNoteControllers;

  /// Λόγος της νέας αναβολής — ξεχωριστός από τις σημειώσεις των παλιών.
  late final SpellCheckController _snoozeReasonController;
  late int _priority;
  late DateTime _dueDate;
  bool _userPickedDue = false;

  /// Απόφαση για ολοκληρωμένη εκκρεμότητα — προεπιλογή η ασφαλέστερη.
  ClosedTaskSaveMode _closedMode = ClosedTaskSaveMode.stayClosed;

  /// Αποθηκευμένες τιμές για επαναφορά όταν η επιλογή γυρίσει σε
  /// «Παραμένει ολοκληρωμένη»: πεδίο που έπαψε να φαίνεται ή να επιτρέπεται
  /// δεν αποθηκεύει κρυφά ό,τι πρόλαβε να πειραχτεί.
  late final int _originalPriority;
  late final DateTime _originalDue;

  static const List<int> _priorityValues = [0, 1, 2];
  static const List<String> _priorityLabels = ['Κανονική', 'Υψηλή', 'Κρίσιμη'];

  bool get _isClosedTask =>
      widget.task != null &&
      TaskStatusX.fromString(widget.task!.status) == TaskStatus.closed;

  /// Η προθεσμία αφορά εκκρεμότητα που ζει: κρύβεται μόνο όσο μένει
  /// ολοκληρωμένη.
  bool get _deadlineVisible =>
      !_isClosedTask || _closedMode != ClosedTaskSaveMode.stayClosed;

  bool get _isSnoozing =>
      _isClosedTask && _closedMode == ClosedTaskSaveMode.snoozeAgain;

  bool get _priorityEnabled =>
      !_isClosedTask || _closedMode != ClosedTaskSaveMode.stayClosed;

  @override
  void initState() {
    super.initState();
    if (widget.task != null) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(taskSmartEntityProvider.notifier).loadFromTask(widget.task!);
      });
    }
    final t = widget.task;
    _titleController = SpellCheckController()..text = t?.title ?? '';
    // Καθαρή περιγραφή: ο δείκτης «[QUICK_ADD]» είναι μηχανικός και ξαναμπαίνει
    // μόνος του στην αποθήκευση — δεν έχει λόγο να τον βλέπει ή να τον σβήνει
    // ο χρήστης.
    _descriptionController = SpellCheckController()
      ..text = t?.cleanDescription ?? '';
    _snoozeNoteControllers = (t?.snoozeEntries ?? const [])
        .map((e) => SpellCheckController()..text = e.note ?? '')
        .toList();
    _snoozeReasonController = SpellCheckController();
    _priority = t?.priority ?? 0;
    _userPickedDue = t != null;
    _dueDate =
        t?.dueDateTime ??
        ref
            .read(taskServiceProvider)
            .calculateNextDueDate(
              TaskSettingsConfig.defaultConfig(),
              option: TaskSettingsConfig.kOptionDefault,
            );
    _originalPriority = _priority;
    _originalDue = _dueDate;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.task != null || _userPickedDue) return;
      ref.read(taskSettingsConfigProvider.future).then((c) {
        if (!mounted || widget.task != null || _userPickedDue) return;
        setState(() {
          _dueDate = ref
              .read(taskServiceProvider)
              .calculateNextDueDate(
                c,
                option: TaskSettingsConfig.kOptionDefault,
              );
        });
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _providerContainer ??= ProviderScope.containerOf(context);
  }

  @override
  void dispose() {
    final container = _providerContainer;
    if (container != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        container.invalidate(taskSmartEntityProvider);
      });
    }
    _titleController.dispose();
    _descriptionController.dispose();
    _snoozeReasonController.dispose();
    for (final controller in _snoozeNoteControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  TaskSettingsConfig _readSnoozeConfig() =>
      ref
          .read(taskSettingsConfigProvider)
          .maybeWhen(data: (c) => c, orElse: () => null) ??
      TaskSettingsConfig.defaultConfig();

  Future<void> _pickDueDate() async {
    final cfg = _readSnoozeConfig();
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final lastDate = firstDate.add(Duration(days: cfg.maxSnoozeDays));
    var initialDate = DateTime(_dueDate.year, _dueDate.month, _dueDate.day);
    if (initialDate.isBefore(firstDate)) {
      initialDate = firstDate;
    } else if (initialDate.isAfter(lastDate)) {
      initialDate = lastDate;
    }

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate),
    );
    if (!mounted || time == null) return;
    setState(() {
      _userPickedDue = true;
      _dueDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  /// Στιγμή λήξης μιας γρήγορης επιλογής — ο ίδιος υπολογισμός που εφαρμόζεται
  /// όταν πατηθεί, ώστε το chip να μη δείχνει άλλη ώρα από την πραγματική.
  DateTime _quickDue(String option, DateTime from) => ref
      .read(taskServiceProvider)
      .calculateNextDueDate(
        _readSnoozeConfig(),
        option: option,
        fromDate: from,
      );

  /// Κάθε επιλογή ξαναβασίζει τα πεδία που της αναλογούν, ντετερμινιστικά:
  /// «Παραμένει» και «Ξανανοίγει» γυρνούν στα αποθηκευμένα, το «Εκ νέου»
  /// ξεκινά με φρέσκια προθεσμία από τις ρυθμίσεις — καμία τιμή δεν
  /// μεταφέρεται κρυφά από την προηγούμενη επιλογή.
  void _selectClosedMode(ClosedTaskSaveMode mode) {
    setState(() {
      _closedMode = mode;
      switch (mode) {
        case ClosedTaskSaveMode.stayClosed:
          _priority = _originalPriority;
          _dueDate = _originalDue;
        case ClosedTaskSaveMode.reopen:
          _dueDate = _originalDue;
        // Η παλιά λήξη έχει περάσει προ πολλού — και οι δύο ξεκινούν με φρέσκια
        // πρόταση από τις ρυθμίσεις, όπως θα έκανε μια καινούρια εκκρεμότητα.
        case ClosedTaskSaveMode.snoozeAgain:
        case ClosedTaskSaveMode.recreate:
          _dueDate = ref
              .read(taskServiceProvider)
              .calculateNextDueDate(
                _readSnoozeConfig(),
                option: TaskSettingsConfig.kOptionDefault,
              );
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final dueDateStr = _dueDate.toIso8601String();
    final entityState = ref.read(taskSmartEntityProvider);
    final phoneRaw = entityState.phoneText?.trim();
    final phoneText = phoneRaw == null || phoneRaw.isEmpty ? null : phoneRaw;
    String? trimOrNull(String s) {
      final t = s.trim();
      return t.isEmpty ? null : t;
    }

    final typedDescription = _descriptionController.text.trim();
    // Ο δείκτης γρήγορης καταχώρησης επιστρέφει στη θέση του: η φόρμα τον
    // έκρυψε, δεν τον κατάργησε.
    final descriptionToSave = (widget.task?.isQuickAdd ?? false)
        ? Task.withQuickAddTag(typedDescription)
        : (typedDescription.isEmpty ? null : typedDescription);

    final result =
        widget.task?.withFormValues(
          title: title,
          description: descriptionToSave,
          dueDate: dueDateStr,
          priority: _priority,
          updatedAt: DateTime.now().toIso8601String(),
          callerId: entityState.selectedCaller?.id,
          userText: trimOrNull(entityState.callerDisplayText),
          phoneText: phoneText,
          departmentText: trimOrNull(entityState.departmentText),
          equipmentText: trimOrNull(entityState.equipmentText),
        ) ??
        Task(
          title: title,
          description: descriptionToSave,
          dueDate: dueDateStr,
          status: 'open',
          priority: _priority,
          callerId: entityState.selectedCaller?.id,
          userText: trimOrNull(entityState.callerDisplayText),
          phoneText: phoneText,
          departmentText: trimOrNull(entityState.departmentText),
          equipmentText: trimOrNull(entityState.equipmentText),
          origin: Task.originManualFab,
        );

    final Task submitted;
    if (widget.task != null &&
        widget.task!.snoozeEntries.isNotEmpty &&
        _snoozeNoteControllers.length == widget.task!.snoozeEntries.length) {
      submitted = result.withUpdatedSnoozeNotes(
        _snoozeNoteControllers.map((c) => c.text).toList(),
      );
    } else {
      submitted = result;
    }
    final reason = _snoozeReasonController.text.trim();
    Navigator.of(context).pop(
      TaskFormResult(
        submitted,
        closedMode: _isClosedTask ? _closedMode : null,
        snoozeReason: _isSnoozing && reason.isNotEmpty ? reason : null,
      ),
    );
  }

  /// Το κουμπί γράφει πάνω του τη συνέπεια της αποθήκευσης.
  String get _submitLabel {
    if (widget.task == null) return 'Δημιουργία';
    if (!_isClosedTask) return 'Αποθήκευση';
    return switch (_closedMode) {
      ClosedTaskSaveMode.stayClosed => 'Αποθήκευση',
      ClosedTaskSaveMode.reopen => 'Αποθήκευση και άνοιγμα',
      ClosedTaskSaveMode.snoozeAgain => 'Αποθήκευση και αναβολή',
      ClosedTaskSaveMode.recreate => 'Δημιουργία νέας εκκρεμότητας',
    };
  }

  /// Ετικέτα κατάστασης δίπλα στον τίτλο — η φόρμα δηλώνει τι επεξεργάζεται.
  Widget? _buildStatusChip(ThemeData theme) {
    final t = widget.task;
    if (t == null) return null;
    final String label;
    final Color background;
    final Color foreground;
    switch (TaskStatusX.fromString(t.status)) {
      case TaskStatus.open:
        label = 'Ανοιχτή';
        background = theme.colorScheme.surfaceContainerHighest;
        foreground = theme.colorScheme.onSurfaceVariant;
      case TaskStatus.snoozed:
        label = 'Αναβληθείσα';
        background = theme.colorScheme.tertiaryContainer;
        foreground = theme.colorScheme.onTertiaryContainer;
      case TaskStatus.closed:
        label = 'Ολοκληρωμένη';
        background = theme.colorScheme.secondaryContainer;
        foreground = theme.colorScheme.onSecondaryContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }

  /// Το ίδιο όριο που επιβάλλει ο επιλογέας ημερομηνίας, γραμμένο για το μάτι.
  static String _maxSnoozeRangeText(TaskSettingsConfig cfg) =>
      cfg.maxSnoozeDays == 1
      ? 'έως 1 ημέρα'
      : 'έως ${cfg.maxSnoozeDays} ημέρες';

  /// Η προτεραιότητα αφορά εκκρεμότητα που ζει: σε «Παραμένει ολοκληρωμένη»
  /// κλειδώνει, με υπόδειξη που εξηγεί το γιατί. Το key ανά επιλογή ξαναχτίζει
  /// το πεδίο ώστε η επαναφορά της τιμής να φαίνεται και στην οθόνη.
  Widget _buildPriorityField() {
    final field = DropdownButtonFormField<int>(
      key: ValueKey('task_priority_${_closedMode.name}'),
      initialValue: _priority.clamp(0, 2),
      decoration: const InputDecoration(
        labelText: 'Προτεραιότητα',
        border: OutlineInputBorder(),
      ),
      items: List.generate(
        _priorityValues.length,
        (i) => DropdownMenuItem(
          value: _priorityValues[i],
          child: Text(_priorityLabels[i]),
        ),
      ),
      onChanged: _priorityEnabled
          ? (v) => setState(() => _priority = v ?? 0)
          : null,
    );
    if (_priorityEnabled) return field;
    return CompactTooltip(
      message:
          'Η προτεραιότητα αφορά εκκρεμότητα που θα ξανανοίξει — σε '
          '«Παραμένει ολοκληρωμένη» δεν αλλάζει.',
      waitDuration: const Duration(milliseconds: 400),
      child: field,
    );
  }

  Widget _closedModeTile(
    ClosedTaskSaveMode value,
    String title,
    String subtitle,
  ) {
    return RadioListTile<ClosedTaskSaveMode>(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: value,
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(taskSettingsConfigProvider);
    final service = ref.read(taskServiceProvider);
    final cfg =
        ref
            .watch(taskSettingsConfigProvider)
            .maybeWhen(data: (c) => c, orElse: () => null) ??
        TaskSettingsConfig.defaultConfig();
    // Μία στιγμή αναφοράς ανά χτίσιμο: κάθε γρήγορη προθεσμία και η
    // προεπισκόπησή της προκύπτουν από το ίδιο «τώρα».
    final quickDueNow = DateTime.now();
    final suggestedDefault = service.calculateNextDueDate(
      cfg,
      option: TaskSettingsConfig.kOptionDefault,
      fromDate: quickDueNow,
    );

    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);
    final dialogWidth = (mq.width - 48).clamp(400.0, 860.0);
    final hasEntityContent = ref.watch(
      taskSmartEntityProvider.select((s) => s.hasAnyContent),
    );

    final statusChip = _buildStatusChip(theme);
    return DraggableDialogShell(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.task == null
                ? 'Νέα εκκρεμότητα'
                : 'Επεξεργασία εκκρεμότητας',
          ),
          if (statusChip != null) ...[const SizedBox(width: 10), statusChip],
        ],
      ),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        // Το οριζόντιο περιθώριο περνά από το περιεχόμενο του scrollable, ώστε
        // η μπάρα κύλησης να ζωγραφίζεται στην άκρη του διαλόγου και όχι πάνω
        // στα πεδία — εκεί κάθεται η λαβή αλλαγής ύψους.
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),
        content: SizedBox(
          width: dialogWidth + _kDialogHorizontalPadding * 2,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: _kDialogHorizontalPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isClosedTask) ...[
                    _CompletionSummaryBox(task: widget.task!),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const gapsAndTrailing = 120.0;
                          final mw = constraints.maxWidth;
                          final available = (mw - gapsAndTrailing).clamp(
                            200.0,
                            double.infinity,
                          );
                          final w1 = (available * 0.18).clamp(0.0, 170.0);
                          final w2 = (available * 0.34).clamp(0.0, 300.0);
                          final wDept = (available * 0.24).clamp(0.0, 240.0);
                          final w3 = (available * 0.20).clamp(0.0, 185.0);
                          final minRowWidth =
                              w1 +
                              12 +
                              w2 +
                              12 +
                              wDept +
                              12 +
                              w3 +
                              gapsAndTrailing;
                          final selector = SmartEntitySelectorWidget(
                            key: _entitySelectorKey,
                            provider: taskSmartEntityProvider,
                            w1: w1,
                            w2: w2,
                            wDept: wDept,
                            w3: w3,
                            trailingRowChildren: [
                              const SizedBox(width: 4),
                              IgnorePointer(
                                ignoring: !hasEntityContent,
                                child: AnimatedOpacity(
                                  opacity: hasEntityContent ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: AnimatedScale(
                                    scale: hasEntityContent ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 180),
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.clear,
                                        color: theme.colorScheme.error,
                                      ),
                                      tooltip: 'Καθαρισμός πεδίων καλούντα',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 40,
                                        minHeight: 40,
                                      ),
                                      onPressed: () => _entitySelectorKey
                                          .currentState
                                          ?.performClearAllFields(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
                    ),
                  ),
                  const SizedBox(height: 12),
                  LexiconSpellTextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Τίτλος',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Υποχρεωτικό πεδίο'
                        : null,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  ResizableTextArea(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Περιγραφή',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPriorityField(),
                  if (_isClosedTask) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Με την αποθήκευση:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    RadioGroup<ClosedTaskSaveMode>(
                      groupValue: _closedMode,
                      onChanged: (v) {
                        if (v != null) _selectClosedMode(v);
                      },
                      child: Column(
                        children: [
                          _closedModeTile(
                            ClosedTaskSaveMode.stayClosed,
                            'Παραμένει ολοκληρωμένη',
                            'Μόνο διόρθωση κειμένου — η στιγμή και η λύση '
                                'δεν αλλάζουν.',
                          ),
                          _closedModeTile(
                            ClosedTaskSaveMode.reopen,
                            'Ξανανοίγει',
                            'Αναίρεση ολοκλήρωσης — κρατά λύση, δημιουργία '
                                'και ιστορικό αναβολών.',
                          ),
                          _closedModeTile(
                            ClosedTaskSaveMode.snoozeAgain,
                            'Ξανανοίγει με αναβολή',
                            'Ανοιχτή, αλλά όχι τώρα — ορίστε παρακάτω τη νέα '
                                'λήξη και τον λόγο.',
                          ),
                          _closedModeTile(
                            ClosedTaskSaveMode.recreate,
                            'Εκ νέου',
                            'Νέα ανοιχτή εκκρεμότητα χωρίς λύση — η τωρινή '
                                'μένει ολοκληρωμένη στο αρχείο.',
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_deadlineVisible) ...[
                    const SizedBox(height: 12),
                    // Ο λόγος γράφεται ΠΡΙΝ τη νέα λήξη: όποιος διαβάζει με τη
                    // σειρά τον προλαβαίνει, όπως στον διάλογο αναβολής.
                    if (_isSnoozing) ...[
                      ResizableTextArea(
                        key: const ValueKey('snooze_reason'),
                        controller: _snoozeReasonController,
                        decoration: const InputDecoration(
                          labelText: 'Λόγος αναβολής (προαιρετικό)',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        minLines: 2,
                        autoGrowMaxLines: 8,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      _isSnoozing ? 'Γρήγορη νέα λήξη' : 'Γρήγορη προθεσμία',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TaskDueQuickChips(
                      now: quickDueNow,
                      choices: [
                        TaskDueQuickChoice(
                          option: TaskSettingsConfig.kOneHour,
                          label: '+1 ώρα',
                          due: _quickDue(
                            TaskSettingsConfig.kOneHour,
                            quickDueNow,
                          ),
                          message: TaskDueOptionTooltips.plusOneHour(),
                        ),
                        TaskDueQuickChoice(
                          option: TaskSettingsConfig.kDayEnd,
                          label: 'Μέσα στο ωράριο',
                          due: _quickDue(
                            TaskSettingsConfig.kDayEnd,
                            quickDueNow,
                          ),
                          message: TaskDueOptionTooltips.withinSchedule(
                            cfg.nextBusinessHour,
                            cfg.dayEndTime,
                          ),
                        ),
                        TaskDueQuickChoice(
                          option: TaskSettingsConfig.kNextBusiness,
                          label: 'Επόμενη εργάσιμη',
                          due: _quickDue(
                            TaskSettingsConfig.kNextBusiness,
                            quickDueNow,
                          ),
                          message: TaskDueOptionTooltips.nextBusiness(
                            cfg.nextBusinessHour,
                          ),
                        ),
                        TaskDueQuickChoice(
                          option: _kSettingsDefaultOption,
                          label: 'Προεπιλογή ρυθμίσεων',
                          due: suggestedDefault,
                          message:
                              'Η λήξη ορίζεται από την προεπιλεγμένη επιλογή των '
                              'ρυθμίσεων εκκρεμοτήτων.',
                        ),
                      ],
                      onSelected: (choice) => setState(() {
                        _userPickedDue = true;
                        _dueDate = choice.due;
                      }),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _isSnoozing ? 'Νέα λήξη' : 'Ημερομηνία / ώρα λήξης',
                      ),
                      subtitle: Text(
                        '${_dueDate.day}/${_dueDate.month}/${_dueDate.year} ${_dueDate.hour.toString().padLeft(2, '0')}:${_dueDate.minute.toString().padLeft(2, '0')}'
                        '${_isSnoozing ? ' — ${_maxSnoozeRangeText(cfg)}' : ''}',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: _pickDueDate,
                        child: const Text('Επιλογή'),
                      ),
                    ),
                  ],
                  if (widget.task != null &&
                      widget.task!.snoozeEntries.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Αναβολές',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (
                      var i = 0;
                      i < widget.task!.snoozeEntries.length;
                      i++
                    ) ...[
                      Text(
                        'Αναβολή ${i + 1} — '
                        '${DateFormat('dd/MM HH:mm').format(widget.task!.snoozeEntries[i].snoozedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ResizableTextArea(
                        key: ValueKey('snooze_note_$i'),
                        controller: _snoozeNoteControllers[i],
                        decoration: const InputDecoration(
                          labelText: 'Σημείωση αναβολής',
                          hintText: 'Σημείωση αναβολής',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        minLines: 2,
                        autoGrowMaxLines: 8,
                      ),
                      if (i < widget.task!.snoozeEntries.length - 1)
                        const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(onPressed: _submit, child: Text(_submitLabel)),
        ],
      ),
    );
  }
}

/// Σύνοψη της ολοκλήρωσης μέσα στη φόρμα: πότε, πόσο κράτησε, ποια λύση.
class _CompletionSummaryBox extends StatelessWidget {
  const _CompletionSummaryBox({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = TaskCompletionSummary.of(task);

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('Ολοκληρώθηκε', summary.completedAtLabel ?? 'άγνωστη στιγμή'),
          if (summary.durationLabel != null)
            row('Διάρκεια', '${summary.durationLabel} (από τη δημιουργία)'),
          if (summary.sinceLastSnoozeLabel != null)
            row('Από τελευταία αναβολή', summary.sinceLastSnoozeLabel!),
          row('Λύση', summary.solution ?? 'Καθόλου λύση'),
        ],
      ),
    );
  }
}
