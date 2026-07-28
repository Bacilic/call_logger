import 'package:flutter/material.dart';

/// Επιλογή διαγραφής φύλλου κατόψης (τι αποφάσισε ο χρήστης στον διάλογο).
class BuildingMapFloorDeleteChoice {
  const BuildingMapFloorDeleteChoice({required this.deleteImageFile});

  final bool deleteImageFile;
}

/// Διάλογος «Διαγραφή ορόφου»: επιβεβαίωση + διακόπτης οριστικής διαγραφής
/// του αρχείου εικόνας από τον δίσκο. Επιστρέφει null σε ακύρωση.
Future<BuildingMapFloorDeleteChoice?> showBuildingMapFloorDeleteDialog(
  BuildContext context, {
  required String? displayImagePath,
  required bool imageFileExists,
  required bool showMissingImageNote,
}) {
  return showDialog<BuildingMapFloorDeleteChoice>(
    context: context,
    builder: (_) => BuildingMapFloorDeleteDialog(
      displayImagePath: displayImagePath,
      imageFileExists: imageFileExists,
      showMissingImageNote: showMissingImageNote,
    ),
  );
}

class BuildingMapFloorDeleteDialog extends StatefulWidget {
  const BuildingMapFloorDeleteDialog({
    super.key,
    required this.displayImagePath,
    required this.imageFileExists,
    required this.showMissingImageNote,
  });

  /// Πλήρης διαδρομή της εικόνας για εμφάνιση· null όταν δεν υπάρχει εικόνα.
  final String? displayImagePath;

  /// Ενεργοποιεί τον διακόπτη διαγραφής αρχείου.
  final bool imageFileExists;

  /// Σημείωση «το αρχείο εικόνας δεν βρέθηκε στο δίσκο».
  final bool showMissingImageNote;

  @override
  State<BuildingMapFloorDeleteDialog> createState() =>
      _BuildingMapFloorDeleteDialogState();
}

class _BuildingMapFloorDeleteDialogState
    extends State<BuildingMapFloorDeleteDialog> {
  var _deleteImageFile = false;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    final displayImagePath = widget.displayImagePath;
    return AlertDialog(
      title: const Text('Διαγραφή ορόφου'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Να διαγραφεί το φύλλο κατόψης;\n\n'
              'Ο σχεδιασμός στο χάρτη για τα τμήματα που δένονται σε αυτό το φύλλο '
              'θα χαθεί: η θέση και η περιοχή στο χάρτη θα μηδενιστούν.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Διαγραφή αρχείου εικόνας από το δίσκο'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_deleteImageFile)
                    Text(
                      'Η εικόνα του χάρτη θα διαγραφεί οριστικά από το δίσκο.',
                      style: TextStyle(color: errorColor),
                    )
                  else
                    const Text(
                      'Από προεπιλογή η εικόνα διατηρείται στον φάκελο της εφαρμογής.',
                    ),
                  if (displayImagePath != null &&
                      displayImagePath.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      displayImagePath,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else if (widget.showMissingImageNote) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Το αρχείο εικόνας δεν βρέθηκε στο δίσκο.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
              value: _deleteImageFile,
              onChanged: widget.imageFileExists
                  ? (v) => setState(() => _deleteImageFile = v)
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            BuildingMapFloorDeleteChoice(deleteImageFile: _deleteImageFile),
          ),
          child: const Text('Διαγραφή'),
        ),
      ],
    );
  }
}
