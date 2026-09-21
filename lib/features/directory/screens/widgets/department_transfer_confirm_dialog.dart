import 'package:flutter/material.dart';

import '../../models/department_kind.dart';
import '../../services/user_move_consequences.dart';

/// Αποτέλεσμα διαλόγου επιβεβαίωσης αλλαγής τμήματος.
enum DepartmentTransferDialogResult {
  /// Κλείσιμο χωρίς επιβεβαίωση μεταφοράς (επαναφορά πεδίου τμήματος).
  cancelTransfer,

  /// Επιβεβαιωμένη αποθήκευση με το νέο τμήμα.
  confirm,
}

/// Διάλογος «Αλλαγή τμήματος»: τσεκ πριν από τη γραμμή μεταφοράς (προεπιλογή off) και δυναμικό κουμπί.
Future<DepartmentTransferDialogResult?> showDepartmentTransferConfirmDialog({
  required BuildContext context,
  required String userDisplayName,
  required String oldDepartment,
  required String newDepartment,
  required bool newDepartmentExistsInOrg,

  /// Το Είδος του τμήματος που αφήνει και εκείνου που πάει.
  ///
  /// Χωρίς αυτά ο διάλογος λέει τα ίδια ακριβώς λόγια είτε ο άνθρωπος πάει στο
  /// διπλανό γραφείο είτε φεύγει από το νοσοκομείο.
  DepartmentKind previousKind = DepartmentKind.hospital,
  DepartmentKind targetKind = DepartmentKind.hospital,

  /// True: μήνυμα «Προσθήκη … σε …» και κουμπιά Προσθήκη / Προσθήκη + Δημιουργία.
  bool useAddToDepartmentMessage = false,
}) {
  return showDialog<DepartmentTransferDialogResult>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _DepartmentTransferConfirmDialog(
      userDisplayName: userDisplayName,
      oldDepartment: oldDepartment,
      newDepartment: newDepartment,
      newDepartmentExistsInOrg: newDepartmentExistsInOrg,
      previousKind: previousKind,
      targetKind: targetKind,
      useAddToDepartmentMessage: useAddToDepartmentMessage,
    ),
  );
}

class _DepartmentTransferConfirmDialog extends StatefulWidget {
  const _DepartmentTransferConfirmDialog({
    required this.userDisplayName,
    required this.oldDepartment,
    required this.newDepartment,
    required this.newDepartmentExistsInOrg,
    required this.previousKind,
    required this.targetKind,
    required this.useAddToDepartmentMessage,
  });

  final String userDisplayName;
  final String oldDepartment;
  final String newDepartment;
  final bool newDepartmentExistsInOrg;
  final DepartmentKind previousKind;
  final DepartmentKind targetKind;
  final bool useAddToDepartmentMessage;

  @override
  State<_DepartmentTransferConfirmDialog> createState() =>
      _DepartmentTransferConfirmDialogState();
}

class _DepartmentTransferConfirmDialogState
    extends State<_DepartmentTransferConfirmDialog> {
  bool _confirmTransfer = false;

  String get _oldLabel {
    final t = widget.oldDepartment.trim();
    return t.isEmpty ? '—' : t;
  }

  String get _newLabel {
    final t = widget.newDepartment.trim();
    return t.isEmpty ? '—' : t;
  }

  /// Η γραμμή «φεύγει από το νοσοκομείο» — `null` όταν δεν ισχύει.
  String? get _leavesHospitalNote => userLeavesHospitalMessage(
    previousKind: widget.previousKind,
    targetKind: widget.targetKind,
    targetDepartmentName: widget.newDepartment,
    userDisplayName: widget.userDisplayName,
  );

  bool get _needsCreate =>
      widget.newDepartment.trim().isNotEmpty &&
      !widget.newDepartmentExistsInOrg;

  String get _confirmButtonLabel {
    if (widget.useAddToDepartmentMessage) {
      if (!_needsCreate) return 'Προσθήκη';
      return 'Προσθήκη + Δημιουργία';
    }
    if (!_needsCreate) return 'Μεταφορά';
    return 'Μεταφορά + Δημιουργία';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = theme.colorScheme.primary;
    final nameLabel = widget.userDisplayName.trim().isEmpty
        ? '—'
        : widget.userDisplayName.trim();

    return AlertDialog(
      title: Text(
        widget.useAddToDepartmentMessage
            ? 'Προσθήκη σε τμήμα'
            : 'Αλλαγή τμήματος',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: _confirmTransfer,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) =>
                      setState(() => _confirmTransfer = v ?? false),
                ),
                Expanded(
                  child: widget.useAddToDepartmentMessage
                      ? Text.rich(
                          TextSpan(
                            style: theme.textTheme.bodyLarge,
                            children: [
                              const TextSpan(text: 'Προσθήκη '),
                              TextSpan(
                                text: nameLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: ' σε '),
                              TextSpan(
                                text: _newLabel,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: green,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text.rich(
                          TextSpan(
                            style: theme.textTheme.bodyLarge,
                            children: [
                              const TextSpan(text: 'Μεταφορά '),
                              TextSpan(
                                text: nameLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: ' από '),
                              TextSpan(
                                text: _oldLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const TextSpan(text: ' → '),
                              TextSpan(
                                text: _newLabel,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: green,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
            if (_leavesHospitalNote != null) ...[
              const SizedBox(height: 10),
              // Ακριβώς κάτω από το κουτάκι που πρέπει να τσεκαριστεί: η
              // πληροφορία που αλλάζει τη σημασία της πράξης οφείλει να
              // διαβαστεί πριν το τικ, όχι μετά.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer.withValues(
                    alpha: 0.45,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.logout_outlined,
                      size: 18,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _leavesHospitalNote!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_needsCreate) ...[
              const SizedBox(height: 8),
              Text(
                'Το τμήμα «$_newLabel» δεν υπάρχει. Θα δημιουργηθεί στον οργανισμό.',
                textAlign: TextAlign.start,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(DepartmentTransferDialogResult.cancelTransfer),
          child: Text(
            widget.useAddToDepartmentMessage ? 'Ακύρωση' : 'Ακύρωση μεταφοράς',
          ),
        ),
        FilledButton(
          onPressed: _confirmTransfer
              ? () => Navigator.of(
                  context,
                ).pop(DepartmentTransferDialogResult.confirm)
              : null,
          child: Text(_confirmButtonLabel),
        ),
      ],
    );
  }
}
