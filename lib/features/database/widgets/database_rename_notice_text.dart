import 'package:flutter/material.dart';

import '../../../core/widgets/draggable_dialog_shell.dart';
import '../services/create_new_database_texts.dart';

/// Πλάτος σώματος στους διαλόγους επιβεβαίωσης της ροής «νέα βάση».
///
/// Χωρίς όριο το `AlertDialog` απλώνει την παράγραφο σχεδόν σε όλη την οθόνη
/// και η πρόταση γίνεται μία ατέλειωτη γραμμή.
const double _kConfirmationBodyWidth = 480;

/// Διάλογος επιβεβαίωσης με αναδιπλωμένο κείμενο και **έντονο** το όνομα που
/// θα πάρει η τρέχουσα βάση. Μετακινούμενος, όπως οι υπόλοιποι της ροής.
Future<bool?> showDatabaseRenameConfirmationDialog({
  required BuildContext context,
  required String title,
  required RenameNoticeParts parts,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => DraggableDialogShell(
      title: Text(title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: _kConfirmationBodyWidth,
          child: SingleChildScrollView(
            child: DatabaseRenameNoticeText(parts: parts),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

/// Κείμενο οδηγίας με **έντονο** το όνομα αρχείου στη μέση.
///
/// Ένα σημείο απόδοσης για τα τρία μηνύματα της ροής «νέα βάση» — αλλιώς το
/// ίδιο `Text.rich` θα γραφόταν τρεις φορές και θα απέκλιναν στο στυλ.
class DatabaseRenameNoticeText extends StatelessWidget {
  const DatabaseRenameNoticeText({super.key, required this.parts, this.style});

  final RenameNoticeParts parts;

  /// Βασικό στυλ· το όνομα κληρονομεί από αυτό και γίνεται έντονο.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium;
    final name = parts.fileName.trim();

    if (name.isEmpty) {
      return Text(parts.before, style: base);
    }

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: parts.before),
          TextSpan(
            text: name,
            style: base?.copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: parts.after),
        ],
      ),
    );
  }
}
