import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lookup_service.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/models/user_model.dart';
import '../../models/department_model.dart';
import '../../providers/directory_provider.dart';
import '../../services/bulk_user_actions.dart';
import 'bulk_user_action_call_guard.dart';
import 'bulk_user_action_pickers.dart';
import 'shared_asset_disconnect_dialog.dart';

/// Μαζικές ενέργειες υπαλλήλων: μεταφορά σε τμήμα, σημειώσεις, καθαρισμός.
///
/// Καμία φόρμα πεδίων και κανένα κουτάκι επιλογής — μία ενέργεια τη φορά, με
/// ρητή σύνοψη «τι θα συμβεί σε ποιους» πριν από κάθε εκτέλεση. Η πράξη
/// γράφεται ατομικά και αφήνει προσφορά πλήρους αναίρεσης στην καρτέλα.
class BulkUserEditDialog extends ConsumerStatefulWidget {
  const BulkUserEditDialog({
    super.key,
    required this.selectedUsers,
    required this.notifier,
  });

  final List<UserModel> selectedUsers;
  final DirectoryNotifier notifier;

  @override
  ConsumerState<BulkUserEditDialog> createState() => _BulkUserEditDialogState();
}

class _BulkUserEditDialogState extends ConsumerState<BulkUserEditDialog> {
  bool _busy = false;

  List<UserModel> get _users => widget.selectedUsers;

  Set<int> get _selectedIds => {
    for (final u in _users)
      if (u.id != null) u.id!,
  };

  // ─────────────────── Δεδομένα κοινοχρησίας από τον κατάλογο ───────────────────

  Map<int, List<EquipmentModel>> _equipmentByUserId() {
    final lookup = LookupService.instance;
    return {
      for (final u in _users)
        if (u.id != null) u.id!: lookup.findEquipmentsForUser(u.id!),
    };
  }

  BulkAssetSharingInfo _sharingInfo(
    Map<int, List<EquipmentModel>> equipmentByUser,
  ) {
    final lookup = LookupService.instance;
    final selectedIds = _selectedIds;
    final phoneOthers = <String, List<String>>{};
    final phoneDeptNames = <String, String>{};
    final equipmentOthers = <int, List<String>>{};

    for (final u in _users) {
      for (final raw in u.phones) {
        final n = raw.trim();
        if (n.isEmpty || phoneOthers.containsKey(n)) continue;
        final others = [
          for (final other in lookup.findUsersByPhone(n))
            if (other.id != null && !selectedIds.contains(other.id))
              bulkUserDisplayName(other),
        ];
        if (others.isNotEmpty) phoneOthers[n] = others;
        final dept = lookup.getDepartmentByPhone(n);
        final deptName = dept?.name.trim() ?? '';
        if (deptName.isNotEmpty) phoneDeptNames[n] = deptName;
      }
    }
    for (final list in equipmentByUser.values) {
      for (final e in list) {
        final eqId = e.id;
        if (eqId == null || equipmentOthers.containsKey(eqId)) continue;
        final owners = [
          for (final owner in lookup.findUsersForEquipment(eqId))
            if (owner.id != null && !selectedIds.contains(owner.id))
              bulkUserDisplayName(owner),
        ];
        if (owners.isNotEmpty) equipmentOthers[eqId] = owners;
      }
    }
    return BulkAssetSharingInfo(
      phoneOtherUserNames: phoneOthers,
      phoneSharedDepartmentNames: phoneDeptNames,
      equipmentOtherUserNames: equipmentOthers,
    );
  }

  // ─────────────────────────── Κοινά βοηθητικά ροών ───────────────────────────

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
      final allowed = await ensureBulkUserActionAllowed(context, ref, _users);
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
      headerLabel: _users.length == 1
          ? 'Μεταφορά 1 υπαλλήλου σε τμήμα'
          : 'Μεταφορά ${_users.length} υπαλλήλων σε τμήμα',
      availableDepartments: _activeDepartments(),
    );
    if (target == null || !mounted) return;

    final phoneFate = await showBulkOptionDialog<BulkTransferAssetFate>(
      context,
      title: 'Τηλέφωνα των υπαλλήλων',
      message: 'Τι θα γίνουν τα προσωπικά τηλέφωνα των μεταφερόμενων;',
      options: [
        (
          'Μένουν στο παλιό τμήμα',
          'Αποδεσμεύονται από τον υπάλληλο και γίνονται κοινόχρηστα '
              'του τμήματος που αφήνει.',
          BulkTransferAssetFate.stayInOldDepartment,
        ),
        (
          'Ακολουθούν τους υπαλλήλους',
          'Παραμένουν προσωπικά τηλέφωνα των υπαλλήλων στο νέο τμήμα.',
          BulkTransferAssetFate.follow,
        ),
      ],
    );
    if (phoneFate == null || !mounted) return;

    final equipmentFate = await showBulkOptionDialog<BulkTransferAssetFate>(
      context,
      title: 'Εξοπλισμός των υπαλλήλων',
      message: 'Τι θα γίνει ο εξοπλισμός των μεταφερόμενων;',
      options: [
        (
          'Ακολουθεί στο νέο τμήμα',
          'Ο εξοπλισμός αλλάζει τμήμα μαζί με τον κάτοχό του.',
          BulkTransferAssetFate.follow,
        ),
        (
          'Μένει στο παλιό τμήμα',
          'Αποδεσμεύεται από τον υπάλληλο και παραμένει στο τμήμα που αφήνει.',
          BulkTransferAssetFate.stayInOldDepartment,
        ),
      ],
    );
    if (equipmentFate == null || !mounted) return;

    final equipmentByUser = _equipmentByUserId();
    final plan = buildBulkUserTransferPlan(
      selectedUsers: _users,
      target: target,
      targetDisplayName: _targetDisplayName(target),
      phoneFate: phoneFate,
      equipmentFate: equipmentFate,
      equipmentByUserId: equipmentByUser,
      sharing: _sharingInfo(equipmentByUser),
    );
    if (!plan.hasWork) {
      await showBulkInfoDialog(
        context,
        title: 'Καμία μεταφορά',
        message:
            'Όλοι οι επιλεγμένοι υπάλληλοι βρίσκονται ήδη στο '
            '«${plan.targetDisplayName}».',
      );
      return;
    }

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση μεταφοράς',
      message: bulkTransferConfirmationText(plan),
      confirmLabel: 'Μεταφορά',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkTransfer(plan);
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Σημειώσεις ───────────────────────────

  Future<void> _runNotesFlow() async {
    final result = await showBulkNotesDialog(
      context,
      title: 'Σημειώσεις σε ${_users.length} υπαλλήλους',
    );
    if (result == null || !mounted) return;
    final (append, text) = result;
    final mode = append ? BulkNotesMode.append : BulkNotesMode.replace;

    final message = mode == BulkNotesMode.append
        ? 'Θα προστεθεί η σημείωση «$text» στο τέλος των σημειώσεων '
              '${_users.length} υπαλλήλων: ${bulkUserNamesPreview(_users)}.'
        : 'Θα ΑΝΤΙΚΑΤΑΣΤΑΘΟΥΝ οι σημειώσεις ${_users.length} υπαλλήλων '
              'με το κείμενο «$text»: ${bulkUserNamesPreview(_users)}.';
    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση σημειώσεων',
      message: message,
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkNotes(
      users: _users,
      text: text,
      mode: mode,
      message:
          'Ενημερώθηκαν οι σημειώσεις ${_users.length} υπαλλήλων '
          '(${mode == BulkNotesMode.append ? 'προσθήκη' : 'αντικατάσταση'}).',
    );
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Καθαρισμός πεδίου ───────────────────────────

  Future<void> _runClearFlow() async {
    final field = await showBulkOptionDialog<BulkClearField>(
      context,
      title: 'Καθαρισμός πεδίου',
      message: 'Ποιο πεδίο θα καθαριστεί από τους επιλεγμένους υπαλλήλους;',
      options: const [
        ('Τηλέφωνα', null, BulkClearField.phones),
        ('Εξοπλισμός', null, BulkClearField.equipment),
        ('Σημειώσεις', null, BulkClearField.notes),
      ],
    );
    if (field == null || !mounted) return;

    var fate = BulkClearFate.deleteOutright;
    SharedAssetTransferTarget? transferTarget;
    String? transferTargetName;

    if (field != BulkClearField.notes) {
      final what = field == BulkClearField.phones
          ? 'τα τηλέφωνα'
          : 'οι εξοπλισμοί';
      final picked = await showBulkOptionDialog<BulkClearFate>(
        context,
        title: 'Τύχη των στοιχείων',
        message:
            'Μία απάντηση για όλους τους επιλεγμένους: τι θα γίνουν $what;',
        options: const [
          (
            'Αποδέσμευση — κοινόχρηστο στο τμήμα',
            'Το στοιχείο μένει κοινόχρηστο στο τμήμα του κάθε υπαλλήλου.',
            BulkClearFate.shareInOwnDepartment,
          ),
          (
            'Αποδέσμευση και μεταφορά…',
            'Το στοιχείο μεταφέρεται σε τμήμα που θα επιλέξετε.',
            BulkClearFate.transfer,
          ),
          (
            'Οριστική διαγραφή',
            'Το στοιχείο διαγράφεται από τη βάση (με δυνατότητα αναίρεσης).',
            BulkClearFate.deleteOutright,
          ),
        ],
      );
      if (picked == null || !mounted) return;
      fate = picked;
      if (fate == BulkClearFate.transfer) {
        final target = await showAssetTransferTargetPicker(
          context: context,
          headerLabel: field == BulkClearField.phones
              ? 'Μεταφορά τηλεφώνων σε τμήμα'
              : 'Μεταφορά εξοπλισμών σε τμήμα',
          availableDepartments: _activeDepartments(),
        );
        if (target == null || !mounted) return;
        transferTarget = target;
        transferTargetName = _targetDisplayName(target);
      }
    }

    final equipmentByUser = _equipmentByUserId();
    final plan = buildBulkUserClearPlan(
      selectedUsers: _users,
      field: field,
      fate: fate,
      transferTarget: transferTarget,
      transferTargetDisplayName: transferTargetName,
      equipmentByUserId: equipmentByUser,
      sharing: _sharingInfo(equipmentByUser),
    );
    if (!plan.hasWork) {
      final reasons = plan.exclusions.isEmpty
          ? 'Δεν υπάρχει τίποτα προς καθαρισμό στους επιλεγμένους.'
          : plan.exclusions.map((e) => '• ${e.reason}').join('\n');
      await showBulkInfoDialog(
        context,
        title: 'Κανένας καθαρισμός',
        message: reasons,
      );
      return;
    }

    final confirmed = await showBulkConfirmDialog(
      context,
      title: 'Επιβεβαίωση καθαρισμού',
      message: bulkClearConfirmationText(plan),
      confirmLabel: 'Καθαρισμός',
    );
    if (!confirmed || !mounted) return;

    await widget.notifier.applyBulkClear(plan);
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────── Δόμηση ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _users.length == 1
        ? 'Μαζικές ενέργειες — 1 υπάλληλος'
        : 'Μαζικές ενέργειες — ${_users.length} υπάλληλοι';
    return DraggableDialogShell(
      title: Text(title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                bulkUserNamesPreview(_users),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('Μεταφορά σε τμήμα…'),
                  subtitle: const Text(
                    'Υπάρχον ή νέο τμήμα · αποφασίζετε χωριστά για '
                    'τηλέφωνα και εξοπλισμό.',
                  ),
                  enabled: !_busy,
                  onTap: () => _runGuarded(_runTransferFlow),
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.note_add_outlined),
                  title: const Text('Σημειώσεις…'),
                  subtitle: const Text(
                    'Προσθήκη στις υπάρχουσες (προεπιλογή) ή αντικατάσταση.',
                  ),
                  enabled: !_busy,
                  onTap: () => _runGuarded(_runNotesFlow),
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(
                    Icons.cleaning_services_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: const Text('Καθαρισμός πεδίου…'),
                  subtitle: const Text(
                    'Τηλέφωνα, εξοπλισμός ή σημειώσεις — με ρητή '
                    'επιβεβαίωση πριν συμβεί οτιδήποτε.',
                  ),
                  enabled: !_busy,
                  onTap: () => _runGuarded(_runClearFlow),
                ),
              ),
            ],
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
