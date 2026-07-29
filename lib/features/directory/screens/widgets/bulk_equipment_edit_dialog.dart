import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../calls/models/user_model.dart';
import '../../../calls/provider/lookup_provider.dart';
import '../../../calls/provider/remote_paths_provider.dart';
import '../../models/department_model.dart';
import '../../models/equipment_column.dart';
import '../../providers/equipment_directory_provider.dart';
import '../../services/bulk_equipment_actions.dart';
import 'bulk_equipment_action_call_guard.dart';
import 'bulk_user_action_pickers.dart';
import 'shared_asset_disconnect_dialog.dart';

/// Μαζικές ενέργειες εξοπλισμού σε τρεις ομάδες: Οργάνωση, Χαρακτηριστικά,
/// Καθαρισμός.
///
/// Καμία φόρμα πεδίων και κανένα κουτάκι επιλογής — μία ενέργεια τη φορά, με
/// ρητή σύνοψη «τι θα συμβεί σε ποιους» πριν από κάθε εκτέλεση. Ο **Κωδικός**
/// δεν αλλάζει ποτέ μαζικά (είναι ταυτότητα) και ο κάτοχος δένεται ΜΟΝΟ από τη
/// λίστα — ποτέ δεν δημιουργείται υπάλληλος στα κρυφά.
class BulkEquipmentEditDialog extends ConsumerStatefulWidget {
  const BulkEquipmentEditDialog({
    super.key,
    required this.selectedRows,
    required this.notifier,
  });

  final List<EquipmentRow> selectedRows;
  final EquipmentDirectoryNotifier notifier;

  @override
  ConsumerState<BulkEquipmentEditDialog> createState() =>
      _BulkEquipmentEditDialogState();
}

class _BulkEquipmentEditDialogState
    extends ConsumerState<BulkEquipmentEditDialog> {
  bool _busy = false;

  List<EquipmentRow> get _rows => widget.selectedRows;

  // ───────────────────────── Δεδομένα από τον κατάλογο ─────────────────────────

  Map<int, List<UserModel>> _ownersByEquipmentId() {
    final lookup = LookupService.instance;
    return {
      for (final row in _rows)
        if (row.$1.id != null)
          row.$1.id!: lookup.findUsersForEquipment(row.$1.id!),
    };
  }

  List<DepartmentModel> _activeDepartments() {
    return LookupService.instance.departments
        .where((d) => !d.isDeleted && d.name.trim().isNotEmpty)
        .toList();
  }

  String _targetDisplayName(SharedAssetTransferTarget target) {
    final id = target.departmentId;
    if (id != null) {
      return LookupService.instance.getDepartmentName(id) ?? '';
    }
    return target.newDepartmentName?.trim() ?? '';
  }

  Future<void> _runGuarded(Future<void> Function() flow) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final allowed = await ensureBulkEquipmentActionAllowed(
        context,
        ref,
        _rows,
      );
      if (!allowed || !mounted) return;
      await flow();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─────────────────────────── Μεταφορά σε τμήμα ───────────────────────────

  Future<void> _runTransferFlow() async {
    final target = await showAssetTransferTargetPicker(
      context: context,
      headerLabel: _rows.length == 1
          ? 'Μεταφορά 1 εξοπλισμού σε τμήμα'
          : 'Μεταφορά ${_rows.length} εξοπλισμών σε τμήμα',
      availableDepartments: _activeDepartments(),
    );
    if (target == null || !mounted) return;

    final plan = buildBulkEquipmentTransferPlan(
      selectedRows: _rows,
      target: target,
      targetDisplayName: _targetDisplayName(target),
      ownersByEquipmentId: _ownersByEquipmentId(),
    );
    if (!plan.hasWork) {
      await showBulkInfoDialog(
        context,
        title: 'Καμία μεταφορά',
        message:
            'Όλοι οι επιλεγμένοι εξοπλισμοί βρίσκονται ήδη στο '
            '«${plan.targetDisplayName}».',
      );
      return;
    }

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση μεταφοράς',
      message: bulkEquipmentTransferConfirmationText(plan),
      confirmLabel: 'Μεταφορά',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkTransfer(plan);
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Αλλαγή κατόχου ───────────────────────────

  Future<void> _runOwnerFlow() async {
    final owner = await showDialog<UserModel>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _OwnerPickerDialog(),
    );
    if (owner == null || !mounted) return;

    final plan = buildBulkEquipmentOwnerPlan(
      selectedRows: _rows,
      newOwner: owner,
      ownersByEquipmentId: _ownersByEquipmentId(),
    );
    if (!plan.hasWork) {
      await showBulkInfoDialog(
        context,
        title: 'Καμία ανάθεση',
        message: plan.exclusions.isEmpty
            ? 'Δεν υπάρχει εξοπλισμός προς ανάθεση.'
            : plan.exclusions.map((e) => '• ${e.reason}').join('\n'),
      );
      return;
    }

    final deptId = owner.departmentId;
    final deptName = deptId == null
        ? null
        : LookupService.instance.getDepartmentName(deptId);
    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση κατόχου',
      message: bulkEquipmentOwnerConfirmationText(
        plan,
        newOwnerDepartmentName: deptName,
      ),
      confirmLabel: 'Ανάθεση',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkOwner(plan);
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Τοποθεσία ───────────────────────────

  Future<void> _runLocationFlow() async {
    final text = await showBulkTextInputDialog(
      context,
      title: 'Τοποθεσία σε ${_rows.length} εξοπλισμούς',
      label: 'Τοποθεσία',
      helper:
          'Το κενό κείμενο δεν αποθηκεύεται — για διαγραφή χρησιμοποιήστε '
          'τον «Καθαρισμό πεδίου».',
    );
    if (text == null || !mounted) return;

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση τοποθεσίας',
      message:
          'Η τοποθεσία «$text» θα γραφτεί σε ${_rows.length} εξοπλισμούς: '
          '${bulkEquipmentCodesPreview(_rows)}.',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkField(
      rows: _rows,
      column: 'location',
      value: text,
      message: 'Ενημερώθηκε η τοποθεσία ${_rows.length} εξοπλισμών.',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Αλλαγή τύπου ───────────────────────────

  Future<void> _runTypeFlow() async {
    final types = await SettingsService().catalogs.getEquipmentTypesList();
    if (!mounted) return;
    final options = types.where((t) => t.trim().isNotEmpty).toList();
    if (options.isEmpty) {
      await showBulkInfoDialog(
        context,
        title: 'Χωρίς τύπους',
        message:
            'Δεν υπάρχουν καταχωρημένοι τύποι εξοπλισμού στις ρυθμίσεις '
            'καταλόγου.',
      );
      return;
    }

    final picked = await showBulkOptionDialog<String>(
      context,
      title: 'Τύπος εξοπλισμού',
      message: 'Ο τύπος θα γραφτεί σε ${_rows.length} εξοπλισμούς.',
      options: [for (final t in options) (t, null, t)],
    );
    if (picked == null || !mounted) return;

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση τύπου',
      message:
          'Ο τύπος «$picked» θα γραφτεί σε ${_rows.length} εξοπλισμούς: '
          '${bulkEquipmentCodesPreview(_rows)}.',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkField(
      rows: _rows,
      column: 'type',
      value: picked,
      message: 'Ενημερώθηκε ο τύπος ${_rows.length} εξοπλισμών.',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ───────────────── Κύριο εργαλείο απομακρυσμένης ─────────────────

  Future<void> _runPrimaryToolFlow() async {
    final tools = ref.read(remoteToolsCatalogProvider).value ?? const [];
    if (!mounted) return;
    if (tools.isEmpty) {
      await showBulkInfoDialog(
        context,
        title: 'Χωρίς εργαλεία',
        message: 'Δεν υπάρχουν ρυθμισμένα εργαλεία απομακρυσμένης σύνδεσης.',
      );
      return;
    }

    final tool = await showBulkOptionDialog<RemoteTool>(
      context,
      title: 'Κύριο εργαλείο απομακρυσμένης',
      message:
          'Θα οριστεί ως κύριο μόνο σε όσους έχουν ήδη παράμετρο για αυτό '
          'το εργαλείο.',
      options: [for (final t in tools) (t.name, null, t)],
    );
    if (tool == null || !mounted) return;

    final plan = buildBulkEquipmentPrimaryToolPlan(
      selectedRows: _rows,
      tool: tool,
    );
    if (!plan.hasWork) {
      await showBulkInfoDialog(
        context,
        title: 'Καμία αλλαγή',
        message: plan.exclusions.isEmpty
            ? 'Όλοι οι επιλεγμένοι έχουν ήδη το ${tool.name} ως κύριο εργαλείο.'
            : plan.exclusions.map((e) => '• ${e.reason}').join('\n'),
      );
      return;
    }

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση κύριου εργαλείου',
      message: bulkEquipmentPrimaryToolConfirmationText(plan),
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkField(
      rows: plan.rowsToApply,
      column: 'default_remote_tool',
      value: tool.id.toString(),
      message:
          'Το ${tool.name} έγινε κύριο εργαλείο σε '
          '${plan.rowsToApply.length} εξοπλισμούς.',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Σημειώσεις ───────────────────────────

  Future<void> _runNotesFlow() async {
    final result = await showBulkNotesDialog(
      context,
      title: 'Σημειώσεις σε ${_rows.length} εξοπλισμούς',
    );
    if (result == null || !mounted) return;
    final (append, text) = result;

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση σημειώσεων',
      message: append
          ? 'Θα προστεθεί η σημείωση «$text» στο τέλος των σημειώσεων '
                '${_rows.length} εξοπλισμών: '
                '${bulkEquipmentCodesPreview(_rows)}.'
          : 'Θα ΑΝΤΙΚΑΤΑΣΤΑΘΟΥΝ οι σημειώσεις ${_rows.length} εξοπλισμών '
                'με το κείμενο «$text»: ${bulkEquipmentCodesPreview(_rows)}.',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkField(
      rows: _rows,
      column: 'notes',
      value: text,
      notesMode: append
          ? BulkEquipmentNotesMode.append
          : BulkEquipmentNotesMode.replace,
      message:
          'Ενημερώθηκαν οι σημειώσεις ${_rows.length} εξοπλισμών '
          '(${append ? 'προσθήκη' : 'αντικατάσταση'}).',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Καθαρισμός πεδίου ───────────────────────────

  Future<void> _runClearFlow() async {
    final field = await showBulkOptionDialog<BulkEquipmentClearField>(
      context,
      title: 'Καθαρισμός πεδίου',
      message: 'Ποιο πεδίο θα καθαριστεί από τους επιλεγμένους εξοπλισμούς;',
      options: const [
        (
          'Κάτοχος',
          'Αποδέσμευση από τον κάτοχο — ο εξοπλισμός γίνεται κοινόχρηστος '
              'τμήματος, ποτέ ορφανός.',
          BulkEquipmentClearField.owner,
        ),
        ('Σημειώσεις', null, BulkEquipmentClearField.notes),
        ('Τοποθεσία', null, BulkEquipmentClearField.location),
        (
          'Παράμετροι απομακρυσμένης',
          'AnyDesk id, VNC host κ.λπ. — μοναδικά ανά μηχάνημα.',
          BulkEquipmentClearField.remoteParams,
        ),
      ],
    );
    if (field == null || !mounted) return;

    var ownerFate = BulkEquipmentOwnerClearFate.shareInFormerOwnerDepartment;
    SharedAssetTransferTarget? transferTarget;
    String? transferTargetName;

    if (field == BulkEquipmentClearField.owner) {
      final picked = await showBulkOptionDialog<BulkEquipmentOwnerClearFate>(
        context,
        title: 'Πού πάει ο εξοπλισμός',
        message:
            'Μία απάντηση για όλους: μετά την αποδέσμευση, σε ποιο τμήμα '
            'ανήκει ο εξοπλισμός;',
        options: const [
          (
            'Κοινόχρηστος στο τμήμα του πρώην κατόχου',
            'Η φυσική επιλογή — ο εξοπλισμός μένει εκεί που ήταν.',
            BulkEquipmentOwnerClearFate.shareInFormerOwnerDepartment,
          ),
          (
            'Μεταφορά σε άλλο τμήμα…',
            'Επιλέγετε τμήμα προορισμού.',
            BulkEquipmentOwnerClearFate.transfer,
          ),
        ],
      );
      if (picked == null || !mounted) return;
      ownerFate = picked;
      if (ownerFate == BulkEquipmentOwnerClearFate.transfer) {
        final target = await showAssetTransferTargetPicker(
          context: context,
          headerLabel: 'Μεταφορά εξοπλισμών σε τμήμα',
          availableDepartments: _activeDepartments(),
        );
        if (target == null || !mounted) return;
        transferTarget = target;
        transferTargetName = _targetDisplayName(target);
      }
    }

    final plan = buildBulkEquipmentClearPlan(
      selectedRows: _rows,
      field: field,
      ownerFate: ownerFate,
      transferTarget: transferTarget,
      transferTargetDisplayName: transferTargetName,
      ownersByEquipmentId: _ownersByEquipmentId(),
    );
    if (!plan.hasWork) {
      await showBulkInfoDialog(
        context,
        title: 'Κανένας καθαρισμός',
        message: plan.exclusions.isEmpty
            ? 'Δεν υπάρχει τίποτα προς καθαρισμό στους επιλεγμένους.'
            : plan.exclusions.map((e) => '• ${e.reason}').join('\n'),
      );
      return;
    }

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση καθαρισμού',
      message: bulkEquipmentClearConfirmationText(plan),
      confirmLabel: 'Καθαρισμός',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkClear(plan);
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Δόμηση ───────────────────────────

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() flow,
    Color? iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title),
        subtitle: Text(subtitle),
        enabled: !_busy,
        onTap: () => _runGuarded(flow),
      ),
    );
  }

  Widget _groupLabel(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _rows.length == 1
        ? 'Μαζικές ενέργειες — 1 εξοπλισμός'
        : 'Μαζικές ενέργειες — ${_rows.length} εξοπλισμοί';
    return DraggableDialogShell(
      title: Text(title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  bulkEquipmentCodesPreview(_rows),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                _groupLabel('Οργάνωση'),
                _actionCard(
                  icon: Icons.drive_file_move_outline,
                  title: 'Μεταφορά σε τμήμα…',
                  subtitle:
                      'Υπάρχον ή νέο τμήμα · ο εξοπλισμός με κάτοχο '
                      'αποδεσμεύεται και γίνεται κοινόχρηστος.',
                  flow: _runTransferFlow,
                ),
                _actionCard(
                  icon: Icons.person_outline,
                  title: 'Αλλαγή κατόχου…',
                  subtitle:
                      'Μόνο υπάρχων υπάλληλος από τη λίστα · το τμήμα '
                      'ακολουθεί τον νέο κάτοχο.',
                  flow: _runOwnerFlow,
                ),
                _actionCard(
                  icon: Icons.place_outlined,
                  title: 'Τοποθεσία…',
                  subtitle: 'Π.χ. «Γραφείο 3» — το τμήμα δεν θίγεται.',
                  flow: _runLocationFlow,
                ),
                _groupLabel('Χαρακτηριστικά'),
                _actionCard(
                  icon: Icons.category_outlined,
                  title: 'Αλλαγή τύπου…',
                  subtitle: 'Από τους καταχωρημένους τύπους του καταλόγου.',
                  flow: _runTypeFlow,
                ),
                _actionCard(
                  icon: Icons.desktop_windows_outlined,
                  title: 'Κύριο εργαλείο απομακρυσμένης…',
                  subtitle:
                      'Μόνο όπου υπάρχει ήδη παράμετρος · οι παράμετροι '
                      'του καθενός δεν αλλάζουν.',
                  flow: _runPrimaryToolFlow,
                ),
                _actionCard(
                  icon: Icons.note_add_outlined,
                  title: 'Σημειώσεις…',
                  subtitle:
                      'Προσθήκη στις υπάρχουσες (προεπιλογή) ή αντικατάσταση.',
                  flow: _runNotesFlow,
                ),
                _groupLabel('Καθαρισμός'),
                _actionCard(
                  icon: Icons.cleaning_services_outlined,
                  iconColor: theme.colorScheme.error,
                  title: 'Καθαρισμός πεδίου…',
                  subtitle:
                      'Κάτοχος, σημειώσεις, τοποθεσία ή παράμετροι '
                      'απομακρυσμένης — με ρητή επιβεβαίωση.',
                  flow: _runClearFlow,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Κλείσιμο'),
          ),
        ],
      ),
    );
  }
}

/// Επιλογή νέου κατόχου **αποκλειστικά** από τον κατάλογο υπαλλήλων.
///
/// Δεν υπάρχει διαδρομή δημιουργίας υπαλλήλου: παλαιότερα ένα τυπογραφικό
/// λάθος γεννούσε οντότητα-φάντασμα χωρίς τμήμα.
class _OwnerPickerDialog extends ConsumerStatefulWidget {
  const _OwnerPickerDialog();

  @override
  ConsumerState<_OwnerPickerDialog> createState() => _OwnerPickerDialogState();
}

class _OwnerPickerDialogState extends ConsumerState<_OwnerPickerDialog> {
  final _controller = TextEditingController();
  UserModel? _selected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lookupAsync = ref.watch(lookupServiceProvider);
    final users = lookupAsync.value?.service.users ?? const <UserModel>[];
    final query = _controller.text.trim();
    final matches = query.isEmpty
        ? users.take(40).toList()
        : (lookupAsync.value?.service.searchUsersByQuery(query) ??
                  const <UserModel>[])
              .take(40)
              .toList();

    return DraggableDialogShell(
      title: const Text('Νέος κάτοχος'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 460,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Αναζήτηση υπαλλήλου',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: matches.isEmpty
                    ? Center(
                        child: Text(
                          'Κανένας υπάλληλος δεν ταιριάζει.\nΝέος υπάλληλος '
                          'δημιουργείται μόνο από την καρτέλα Υπάλληλοι.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : RadioGroup<int?>(
                        groupValue: _selected?.id,
                        onChanged: (id) => setState(() {
                          _selected = matches
                              .where((u) => u.id == id)
                              .firstOrNull;
                        }),
                        child: ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (context, i) {
                            final u = matches[i];
                            return RadioListTile<int?>(
                              value: u.id,
                              title: Text(u.fullNameWithDepartment),
                              dense: true,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: _selected == null
                ? null
                : () => Navigator.of(context).pop(_selected),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
  }
}
