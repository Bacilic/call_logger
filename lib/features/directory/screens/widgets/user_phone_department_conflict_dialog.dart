import 'package:flutter/material.dart';

import '../../../../core/directory/phone_department_policy.dart';

enum _UserPhoneConflictResolution {
  transferSharedToUserDepartment,
  removeFromOtherUsersAndAssign,
}

/// Διάλογος σύγκρουσης ανάθεσης τηλεφώνου σε χρήστη (cross-department policy).
Future<UserPhoneConflictBatchResult?> showUserPhoneDepartmentConflictDialog(
  BuildContext context, {
  required List<PhoneDepartmentConflict> conflicts,
  required String userDisplayName,
  required String targetDepartmentName,
  int? targetDepartmentId,
}) {
  if (conflicts.isEmpty) {
    return Future.value(const UserPhoneConflictBatchResult());
  }

  return showDialog<UserPhoneConflictBatchResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _UserPhoneDepartmentConflictDialog(
      conflicts: conflicts,
      userDisplayName: userDisplayName,
      targetDepartmentName: targetDepartmentName,
      targetDepartmentId: targetDepartmentId,
    ),
  );
}

class _UserPhoneDepartmentConflictDialog extends StatefulWidget {
  const _UserPhoneDepartmentConflictDialog({
    required this.conflicts,
    required this.userDisplayName,
    required this.targetDepartmentName,
    required this.targetDepartmentId,
  });

  final List<PhoneDepartmentConflict> conflicts;
  final String userDisplayName;
  final String targetDepartmentName;
  final int? targetDepartmentId;

  @override
  State<_UserPhoneDepartmentConflictDialog> createState() =>
      _UserPhoneDepartmentConflictDialogState();
}

class _UserPhoneDepartmentConflictDialogState
    extends State<_UserPhoneDepartmentConflictDialog> {
  final Map<String, _UserPhoneConflictResolution?> _decisions = {};

  bool get _allResolved =>
      widget.conflicts.every((c) => _decisions[c.phone] != null);

  List<_UserPhoneConflictResolution> _optionsFor(PhoneDepartmentConflict c) {
    final options = <_UserPhoneConflictResolution>[];
    if (c.canTransferSharedLocation && widget.targetDepartmentId != null) {
      options.add(_UserPhoneConflictResolution.transferSharedToUserDepartment);
    }
    if (c.hasOtherUserOwners &&
        (!c.hasDepartmentLocationConflict ||
            widget.targetDepartmentId == null ||
            !c.canTransferSharedLocation)) {
      options.add(_UserPhoneConflictResolution.removeFromOtherUsersAndAssign);
    }
    return options;
  }

  String _detailsText(PhoneDepartmentConflict c) {
    final parts = <String>[];
    if (c.hasDepartmentLocationConflict &&
        (c.existingDepartmentName?.isNotEmpty ?? false)) {
      parts.add('Κοινόχρηστο στο τμήμα «${c.existingDepartmentName}»');
    } else if (c.hasDepartmentLocationConflict) {
      parts.add('Κοινόχρηστο σε άλλο τμήμα');
    }
    if (c.otherUserOwnerLabels.isNotEmpty) {
      parts.add('Κάτοχοι: ${c.otherUserOwnerLabels.join(', ')}');
    }
    return parts.join(' | ');
  }

  Widget _resolutionLabel(
    PhoneDepartmentConflict c,
    _UserPhoneConflictResolution resolution,
  ) {
    switch (resolution) {
      case _UserPhoneConflictResolution.transferSharedToUserDepartment:
        final employee = widget.userDisplayName.trim().isEmpty
            ? '—'
            : widget.userDisplayName.trim();
        final targetDept = widget.targetDepartmentName.trim();
        final sourceDept = c.existingDepartmentName?.trim();
        final employeePart = targetDept.isEmpty
            ? employee
            : '$employee ($targetDept)';
        final removalPart = (sourceDept != null && sourceDept.isNotEmpty)
            ? ' - Αφαίρεση από «$sourceDept»'
            : '';
        return Text('Μεταφορά αριθμού στον υπάλληλο $employeePart$removalPart');
      case _UserPhoneConflictResolution.removeFromOtherUsersAndAssign:
        return const Text(
          'Αφαίρεση από άλλους χρήστες και σύνδεση με αυτόν τον χρήστη',
        );
    }
  }

  UserPhoneConflictBatchResult _buildResult() {
    final transfers = <String, int>{};
    final removeFromOthers = <String>{};
    for (final c in widget.conflicts) {
      final choice = _decisions[c.phone];
      if (choice == null) continue;
      switch (choice) {
        case _UserPhoneConflictResolution.transferSharedToUserDepartment:
          final sourceId = c.existingDepartmentId;
          if (sourceId != null) transfers[c.phone] = sourceId;
          if (c.hasOtherUserOwners) removeFromOthers.add(c.phone);
        case _UserPhoneConflictResolution.removeFromOtherUsersAndAssign:
          removeFromOthers.add(c.phone);
      }
    }
    return UserPhoneConflictBatchResult(
      phonesToTransferShared: transfers,
      phonesToRemoveFromOtherUsers: removeFromOthers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desiredHeight = (widget.conflicts.length * 148.0)
        .clamp(220.0, 520.0)
        .toDouble();
    final targetLabel = widget.targetDepartmentName.trim().isEmpty
        ? '—'
        : widget.targetDepartmentName.trim();

    return AlertDialog(
      title: const Text('Σύγκρουση τοποθεσίας τηλεφώνου'),
      content: SizedBox(
        width: 680,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: desiredHeight),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Το τμήμα του χρήστη είναι «$targetLabel». '
                  'Τα παρακάτω τηλέφωνα συγκρούονται με την πολιτική '
                  'ενός αριθμού ανά τμήμα. Επιλέξτε ενέργεια ή ακυρώστε.',
                ),
                const SizedBox(height: 10),
                for (final c in widget.conflicts) ...[
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Τηλέφωνο: ${c.phone}',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(_detailsText(c)),
                          if (_optionsFor(c).isEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Δεν είναι δυνατή μεταφορά χωρίς τμήμα χρήστη. '
                              'Ακυρώστε ή ορίστε τμήμα.',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ] else ...[
                            const SizedBox(height: 6),
                            RadioGroup<_UserPhoneConflictResolution>(
                              groupValue: _decisions[c.phone],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _decisions[c.phone] = v);
                              },
                              child: Column(
                                children: [
                                  for (final option in _optionsFor(c))
                                    RadioListTile<_UserPhoneConflictResolution>(
                                      dense: true,
                                      value: option,
                                      title: _resolutionLabel(c, option),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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
        FilledButton(
          onPressed: _allResolved &&
                  widget.conflicts.every((c) => _optionsFor(c).isNotEmpty)
              ? () => Navigator.of(context).pop(_buildResult())
              : null,
          child: const Text('Επιβεβαίωση'),
        ),
      ],
    );
  }
}
