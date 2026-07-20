import 'package:flutter/material.dart';

import '../../models/department_model.dart';
import '../../services/department_employee_reassignment_draft.dart';
import 'shared_asset_disconnect_dialog.dart';

/// Υπάλληλος προς μεταφορά κατά τη διαγραφή τμήματος (id + εμφανιζόμενο όνομα).
class DepartmentEmployeeReassignCandidate {
  const DepartmentEmployeeReassignCandidate({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;
}

/// Αποτέλεσμα οδηγού μεταφοράς υπαλλήλων: userId → τμήμα προορισμού.
class DepartmentEmployeeReassignBatch {
  const DepartmentEmployeeReassignBatch({required this.transfers});

  final Map<int, SharedAssetTransferTarget> transfers;
}

/// Οδηγός μεταφοράς υπαλλήλων τμήματος (ανά ομάδες) πριν τη διαγραφή.
///
/// Επιστρέφει `null` αν ο χρήστης ακυρώσει τον διάλογο (ακύρωση όλης της διαγραφής).
Future<DepartmentEmployeeReassignBatch?> showDepartmentEmployeeReassignFlow({
  required BuildContext context,
  required String sourceDepartmentName,
  required List<DepartmentEmployeeReassignCandidate> employees,
  required List<DepartmentModel> availableDepartments,
  required int sourceDepartmentId,
}) async {
  if (employees.isEmpty) {
    return const DepartmentEmployeeReassignBatch(transfers: {});
  }
  if (!context.mounted) return null;

  return showDialog<DepartmentEmployeeReassignBatch>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DepartmentEmployeeReassignDialog(
      sourceDepartmentName: sourceDepartmentName,
      employees: employees,
      availableDepartments: availableDepartments,
      sourceDepartmentId: sourceDepartmentId,
    ),
  );
}

class _DepartmentEmployeeReassignDialog extends StatefulWidget {
  const _DepartmentEmployeeReassignDialog({
    required this.sourceDepartmentName,
    required this.employees,
    required this.availableDepartments,
    required this.sourceDepartmentId,
  });

  final String sourceDepartmentName;
  final List<DepartmentEmployeeReassignCandidate> employees;
  final List<DepartmentModel> availableDepartments;
  final int sourceDepartmentId;

  @override
  State<_DepartmentEmployeeReassignDialog> createState() =>
      _DepartmentEmployeeReassignDialogState();
}

class _DepartmentEmployeeReassignDialogState
    extends State<_DepartmentEmployeeReassignDialog> {
  late final EmployeeReassignmentDraft _draft;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _draft = EmployeeReassignmentDraft(widget.employees);
  }

  String _employeeLabel(DepartmentEmployeeReassignCandidate e) {
    final n = e.name.trim();
    return n.isEmpty ? '?' : n;
  }

  String _targetLabel(SharedAssetTransferTarget target) {
    final newName = target.newDepartmentName?.trim();
    if (newName != null && newName.isNotEmpty) {
      return 'νέο: $newName';
    }
    final id = target.departmentId;
    if (id == null) return '—';
    for (final d in widget.availableDepartments) {
      if (d.id == id) {
        final name = d.name.trim();
        return name.isEmpty ? '—' : name;
      }
    }
    return '—';
  }

  Future<void> _transferSelected() async {
    if (_selected.isEmpty) return;
    final n = _selected.length;
    final target = await showAssetTransferTargetPicker(
      context: context,
      headerLabel: 'Πού μεταφέρονται οι επιλεγμένοι ($n);',
      availableDepartments: widget.availableDepartments,
      sourceDepartmentId: widget.sourceDepartmentId,
    );
    if (!mounted || target == null) return;
    setState(() {
      _draft.assign(Set<int>.from(_selected), target);
      _selected.clear();
    });
  }

  void _toggleAll(bool? value) {
    setState(() {
      if (value == true) {
        _selected
          ..clear()
          ..addAll(_draft.remaining.map((e) => e.id));
      } else {
        _selected.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _draft.remaining;
    final selectedCount = _selected.length;
    final allSelected =
        remaining.isNotEmpty && selectedCount == remaining.length;
    final sourceLabel = widget.sourceDepartmentName.trim().isEmpty
        ? '—'
        : widget.sourceDepartmentName.trim();

    return AlertDialog(
      title: Text('Μεταφορά υπαλλήλων από «$sourceLabel»'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (remaining.isNotEmpty) ...[
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: allSelected,
                  onChanged: _toggleAll,
                  title: Text(
                    'Επιλογή όλων (${remaining.length})',
                    style: theme.textTheme.bodyMedium,
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const Divider(height: 12),
                for (final e in remaining)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(e.id),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(e.id);
                        } else {
                          _selected.remove(e.id);
                        }
                      });
                    },
                    title: Text(_employeeLabel(e)),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Επιλεγμένοι: $selectedCount',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ] else
                Text(
                  'Όλοι οι υπάλληλοι έχουν ανατεθεί.',
                  style: theme.textTheme.bodyMedium,
                ),
              if (_draft.assignedCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Ήδη ανατεθειμένοι',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                for (final e in widget.employees)
                  if (_draft.assignments.containsKey(e.id))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${_employeeLabel(e)} → ${_targetLabel(_draft.assignments[e.id]!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        if (!_draft.isComplete)
          FilledButton(
            onPressed: selectedCount >= 1 ? _transferSelected : null,
            child: Text('Μεταφορά επιλεγμένων ($selectedCount) σε…'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_draft.build()),
            child: const Text('Ολοκλήρωση'),
          ),
      ],
    );
  }
}
