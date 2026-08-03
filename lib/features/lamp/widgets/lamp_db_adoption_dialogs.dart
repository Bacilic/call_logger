import 'package:flutter/material.dart';

import '../../../core/widgets/draggable_dialog_shell.dart';

/// Πού θα ζει η βάση που επέλεξε ο χρήστης.
enum LampDbPlacementChoice { copyToAppFolder, readInPlace, cancel }

/// Τι γίνεται όταν στον φάκελο της εφαρμογής υπάρχει ήδη ομώνυμο αρχείο.
enum LampDbConflictChoice { keepBoth, replace, cancel }

/// Πλάτος σώματος: αρκετό για διαδρομές, αρκετά μικρό ώστε να φαίνεται το πίσω.
const double _kDialogBodyWidth = 460;

/// Τίτλος με λαβή συρσίματος — ίδιο μοτίβο με τους υπόλοιπους κινητούς διαλόγους.
Widget _draggableTitle(BuildContext context, String text) {
  final theme = Theme.of(context);
  return Row(
    children: [
      Expanded(child: Text(text, style: theme.textTheme.titleMedium)),
      Icon(
        Icons.open_with,
        size: 16,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ],
  );
}

/// Γραμμή «ετικέτα + πλήρης διαδρομή» — η διαδρομή σε δική της σειρά, επιλέξιμη.
class _PathBlock extends StatelessWidget {
  const _PathBlock({required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          SelectableText(
            path,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ρωτά αν η επιλεγμένη βάση θα αντιγραφεί στον φάκελο της εφαρμογής ή θα
/// διαβάζεται από τη θέση της. Εμφανίζει και τις δύο πλήρεις διαδρομές.
Future<LampDbPlacementChoice> askLampDbPlacement(
  BuildContext context, {
  required String pickedPath,
  required String appFolderPath,
}) async {
  final choice = await showDialog<LampDbPlacementChoice>(
    context: context,
    builder: (ctx) => DraggableDialogShell(
      title: _draggableTitle(ctx, 'Πού θα βρίσκεται η βάση της Λάμπας;'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        content: SizedBox(
          width: _kDialogBodyWidth,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PathBlock(label: 'Επιλέξατε το αρχείο:', path: pickedPath),
                _PathBlock(
                  label: 'Φάκελος της εφαρμογής:',
                  path: appFolderPath,
                ),
                const SizedBox(height: 4),
                Text(
                  'Αντιγραφή στον φάκελο: το αντίγραφο ταξιδεύει μαζί με την '
                  'εφαρμογή και μπαίνει στα αντίγραφα ασφαλείας. Το αρχείο '
                  'που επιλέξατε μένει ανέπαφο.\n\n'
                  'Ανάγνωση από τη θέση του: δεν αντιγράφεται τίποτα.',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(LampDbPlacementChoice.cancel),
            child: const Text('Ακύρωση'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(LampDbPlacementChoice.readInPlace),
            child: const Text('Ανάγνωση από τη θέση του'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(LampDbPlacementChoice.copyToAppFolder),
            child: const Text('Αντιγραφή στον φάκελο'),
          ),
        ],
      ),
    ),
  );
  return choice ?? LampDbPlacementChoice.cancel;
}

/// Σύγκρουση ονόματος κατά την αντιγραφή: διατήρηση και των δύο ή αντικατάσταση.
///
/// Το [keepBothPath] είναι η πλήρης διαδρομή που θα πάρει το αντίγραφο αν
/// επιλεγεί «Διατήρηση και των δύο».
Future<LampDbConflictChoice> askLampDbCopyConflict(
  BuildContext context, {
  required String sourcePath,
  required String destinationPath,
  required String keepBothPath,
  required bool destinationIsConfiguredOutput,
}) async {
  final choice = await showDialog<LampDbConflictChoice>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return DraggableDialogShell(
        title: _draggableTitle(ctx, 'Υπάρχει ήδη αρχείο με αυτό το όνομα'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          content: SizedBox(
            width: _kDialogBodyWidth,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PathBlock(label: 'Αντιγραφή από:', path: sourcePath),
                  _PathBlock(label: 'Υπάρχον αρχείο:', path: destinationPath),
                  if (destinationIsConfiguredOutput)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Προσοχή: το υπάρχον αρχείο είναι η βάση που '
                        'δημιουργεί το Excel. Η αντικατάσταση θα το σβήσει.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  _PathBlock(
                    label: 'Διατήρηση και των δύο — το αντίγραφο θα γίνει:',
                    path: keepBothPath,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Η «Διατήρηση και των δύο» δεν πειράζει το υπάρχον '
                    'αρχείο. Η «Αντικατάσταση» το σβήνει οριστικά.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(LampDbConflictChoice.cancel),
              child: const Text('Ακύρωση'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(LampDbConflictChoice.replace),
              child: Text(
                'Αντικατάσταση',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(LampDbConflictChoice.keepBoth),
              child: const Text('Διατήρηση και των δύο'),
            ),
          ],
        ),
      );
    },
  );
  return choice ?? LampDbConflictChoice.cancel;
}
