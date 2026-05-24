import 'package:flutter/material.dart';

import '../../../core/database/user_delete_phone_policy.dart';

/// Διάλογος F2-02: μόνο για τηλέφωνα 1↔1 με τον χρήστη που διαγράφεται.
Future<UserDeleteExclusivePhoneAction?> showUserDeleteExclusivePhoneDialog(
  BuildContext context, {
  required List<ExclusivePhoneForUserDelete> phones,
}) {
  if (phones.isEmpty) return Future.value(null);

  final canKeepAtDepartment = phones.any((p) => p.departmentId != null);
  final numbers = phones.map((p) => p.number).toSet().join(', ');
  final deptNames = phones
      .map((p) => p.departmentName?.trim())
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toSet();
  final deptHint = deptNames.isEmpty
      ? ''
      : '\n\nΤμήμα(τα): ${deptNames.join(', ')}.';

  return showDialog<UserDeleteExclusivePhoneAction>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Τηλέφωνο χρήστη'),
      content: Text(
        'Το νούμερο $numbers συνδέεται μόνο με '
        '${phones.length == 1 ? 'αυτόν τον χρήστη' : 'τους χρήστες που διαγράφετε'}.'
        '$deptHint\n\n'
        'Να μείνει στο τμήμα ή να αφαιρεθεί από τον κατάλογο;',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Ακύρωση'),
        ),
        if (canKeepAtDepartment)
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(UserDeleteExclusivePhoneAction.keepAtDepartment),
            child: const Text('Μένει στο τμήμα'),
          ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(UserDeleteExclusivePhoneAction.removePhone),
          child: const Text('Αφαίρεση τηλεφώνου'),
        ),
      ],
    ),
  );
}
