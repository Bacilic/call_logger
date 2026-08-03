import 'package:flutter/material.dart';

import '../../../../core/widgets/draggable_dialog_shell.dart';

/// Απόφαση του φρουρού «νέος υπάλληλος χωρίς τμήμα».
///
/// Η ακύρωση επιστρέφεται ως `null` από τον διάλογο.
enum UserNoDepartmentWarningChoice {
  /// Αποθήκευση όπως είναι, χωρίς τμήμα.
  continueWithoutDepartment,

  /// Άνοιγμα του επιλογέα τμήματος (υπάρχον ή νέο) για εκχώρηση επιτόπου.
  assignToDepartment,
}

/// Προειδοποίηση πριν αποθηκευτεί ΝΕΟΣ υπάλληλος χωρίς τμήμα.
///
/// Είναι ο τελευταίος έλεγχος της ροής — γι' αυτό προσφέρει τη λύση επιτόπου
/// (εκχώρηση σε τμήμα) αντί να στέλνει τον χρήστη να ξανακάνει όλα τα βήματα.
Future<UserNoDepartmentWarningChoice?> showUserNoDepartmentWarningDialog(
  BuildContext context, {
  required String userDisplayName,
}) {
  final name = userDisplayName.trim();
  final subject = name.isEmpty
      ? 'Ο νέος υπάλληλος'
      : 'Ο νέος υπάλληλος «$name»';

  return showDialog<UserNoDepartmentWarningChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DraggableDialogShell(
      title: const Text('Υπάλληλος χωρίς τμήμα'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 460,
          child: Text('$subject δεν έχει εκχωρηθεί σε τμήμα.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ακύρωση'),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              ctx,
            ).pop(UserNoDepartmentWarningChoice.continueWithoutDepartment),
            child: const Text('Συνέχεια χωρίς τμήμα'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              ctx,
            ).pop(UserNoDepartmentWarningChoice.assignToDepartment),
            child: const Text('Εκχώρηση σε τμήμα'),
          ),
        ],
      ),
    ),
  );
}
