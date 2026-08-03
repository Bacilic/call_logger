import 'package:flutter/material.dart';

import '../../../../core/directory/phone_department_policy.dart';
import '../../../../core/utils/transfer_action_messages.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';

/// Διάλογος σύγκρουσης ανάθεσης τηλεφώνου σε χρήστη (cross-department policy).
///
/// Καθαρή παρουσίαση: ποιες διέξοδοι προσφέρονται και τι κάνει η καθεμιά στη
/// βάση αποφασίζει το [PhoneDepartmentPolicy].
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
  final Map<String, UserPhoneConflictResolution?> _decisions = {};

  bool get _allResolved =>
      widget.conflicts.every((c) => _decisions[c.phone] != null);

  List<UserPhoneConflictResolution> _optionsFor(PhoneDepartmentConflict c) {
    return PhoneDepartmentPolicy.availableResolutions(
      c,
      targetDepartmentId: widget.targetDepartmentId,
    );
  }

  /// Εικονίδιο με το κείμενό του· η επεξήγηση λέει τι σημαίνει το εικονίδιο.
  Widget _detailChip(
    ThemeData theme,
    IconData icon,
    String tooltip,
    String text, {
    TextStyle? style,
  }) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: style)),
        ],
      ),
    );
  }

  /// Αριθμός, κοινόχρηστο τμήμα και κάτοχοι σε μία γραμμή με εικονίδια. Το
  /// ανθρωπάκι μπαίνει μόνο όταν υπάρχουν κάτοχοι-υπάλληλοι.
  Widget _detailsRow(ThemeData theme, PhoneDepartmentConflict c) {
    final department = c.existingDepartmentName?.trim();
    final owners = c.otherUserOwnerLabels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();

    return Wrap(
      spacing: 18,
      runSpacing: 4,
      children: [
        _detailChip(
          theme,
          Icons.phone_outlined,
          'Τηλέφωνο',
          c.phone,
          style: theme.textTheme.titleSmall,
        ),
        if (c.hasDepartmentLocationConflict)
          _detailChip(
            theme,
            Icons.apartment_outlined,
            'Κοινόχρηστο στο τμήμα',
            (department == null || department.isEmpty)
                ? 'Άλλο τμήμα'
                : department,
          ),
        if (owners.isNotEmpty)
          _detailChip(
            theme,
            Icons.person_outline,
            owners.length == 1 ? 'Κάτοχος' : 'Κάτοχοι',
            owners.join(', '),
          ),
      ],
    );
  }

  /// «Όνομα (τμήμα)» του υπαλλήλου που θα πάρει τον αριθμό.
  String get _assignTargetLabel {
    final employee = widget.userDisplayName.trim();
    final department = widget.targetDepartmentName.trim();
    final name = employee.isEmpty ? 'τον υπάλληλο που καταχωρείτε' : employee;
    return department.isEmpty ? name : '$name ($department)';
  }

  /// Η ετικέτα περιγράφει ακριβώς ό,τι λέει η πολιτική ότι θα γίνει.
  String _resolutionText(
    PhoneDepartmentConflict c,
    UserPhoneConflictResolution resolution,
  ) {
    final effects = PhoneDepartmentPolicy.resolutionEffects(c, resolution);
    return removeAndAssignMessage(
      sources: [
        if (effects.removesSharedDepartment)
          sharedDepartmentSource(c.existingDepartmentName),
        if (effects.removesOtherUsers)
          ownerNamesForMessage(
            c.otherUserOwnerLabels,
            ifEmpty: 'άλλους χρήστες',
          ),
      ],
      target: _assignTargetLabel,
    );
  }

  UserPhoneConflictBatchResult _buildResult() {
    return PhoneDepartmentPolicy.buildBatchResult(
      conflicts: widget.conflicts,
      decisions: _decisions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desiredHeight = (widget.conflicts.length * 158.0)
        .clamp(220.0, 520.0)
        .toDouble();
    final targetDepartment = widget.targetDepartmentName.trim();
    // Χωρίς τμήμα υπαλλήλου η επίκληση της πολιτικής τμημάτων είναι άστοχη —
    // η κάρτα από κάτω λέει ήδη ποιος κρατά τον αριθμό.
    final introText = targetDepartment.isEmpty
        ? 'Ο υπάλληλος δεν έχει τμήμα. Επιλέξτε ενέργεια ή ακυρώστε.'
        : 'Το τμήμα του υπαλλήλου είναι «$targetDepartment». '
              'Τα παρακάτω τηλέφωνα συγκρούονται με την πολιτική: '
              'ένας αριθμός ανήκει μόνο σε ένα τμήμα. '
              'Επιλέξτε ενέργεια ή ακυρώστε.';

    return DraggableDialogShell(
      title: const Text('Σύγκρουση τοποθεσίας τηλεφώνου'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 680,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: desiredHeight),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(introText),
                  const SizedBox(height: 10),
                  for (final c in widget.conflicts) ...[
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _detailsRow(theme, c),
                            if (_optionsFor(c).isEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Δεν είναι δυνατή μεταφορά χωρίς τμήμα '
                                'υπαλλήλου. Ακυρώστε ή ορίστε τμήμα.',
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 6),
                              RadioGroup<UserPhoneConflictResolution>(
                                groupValue: _decisions[c.phone],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _decisions[c.phone] = v);
                                },
                                child: Column(
                                  children: [
                                    for (final option in _optionsFor(c))
                                      RadioListTile<
                                        UserPhoneConflictResolution
                                      >(
                                        dense: true,
                                        value: option,
                                        title: Text(_resolutionText(c, option)),
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
            onPressed:
                _allResolved &&
                    widget.conflicts.every((c) => _optionsFor(c).isNotEmpty)
                ? () => Navigator.of(context).pop(_buildResult())
                : null,
            child: const Text('Επιβεβαίωση'),
          ),
        ],
      ),
    );
  }
}
