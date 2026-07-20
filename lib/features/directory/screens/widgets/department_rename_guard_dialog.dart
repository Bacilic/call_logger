import 'package:flutter/material.dart';

/// Επιλογή στη δικλείδα «μοιάζει με μετονομασία».
enum DepartmentRenameGuardChoice {
  renameInstead,
  proceedDelete,
  cancel,
}

/// Διάλογος δικλείδας όταν η μαζική μεταφορά σε νέο τμήμα μοιάζει με μετονομασία.
Future<DepartmentRenameGuardChoice?> showDepartmentRenameGuardDialog({
  required BuildContext context,
  required String sourceDepartmentName,
  required String proposedNewName,
}) {
  final source = sourceDepartmentName.trim().isEmpty
      ? '—'
      : sourceDepartmentName.trim();
  final proposed =
      proposedNewName.trim().isEmpty ? '—' : proposedNewName.trim();

  return showDialog<DepartmentRenameGuardChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Μοιάζει με μετονομασία, όχι διάλυση τμήματος'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Text(
            'Μεταφέρετε τα πάντα από «$source» σε νέο τμήμα «$proposed». '
            'Αν πρόκειται για μετονομασία, η δημιουργία νέου τμήματος χάνει:\n'
            '• τη θέση και το χρώμα στον χάρτη κτιρίου\n'
            '• τον όροφο και την ομάδα\n'
            '• τη συνέχεια στις αναφορές (ένα τμήμα αντί για δύο)\n'
            '• το παλιό ιστορικό του τμήματος',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(DepartmentRenameGuardChoice.cancel),
          child: const Text('Ακύρωση'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx)
              .pop(DepartmentRenameGuardChoice.proceedDelete),
          child: const Text('Ναι, το τμήμα διαλύεται — συνέχεια'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(DepartmentRenameGuardChoice.renameInstead),
          child: const Text('Μετονομασία αντ\' αυτού'),
        ),
      ],
    ),
  );
}
