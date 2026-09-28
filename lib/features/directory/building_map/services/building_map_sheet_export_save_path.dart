import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/file_picker_initial_directory.dart';
import '../../../../core/utils/file_picker_session.dart';

enum _ExportKind { png, jpeg }

/// Διάλογος αποθήκευσης για εξαγωγή χάρτη.
///
/// Επιλογή τύπου σε [AlertDialog] και μετά `FilePicker.saveFile` με ένα φίλτρο
/// τη φορά (ώστε να μην εμφανίζονται και οι τρεις επεκτάσεις μαζί). Ο επιλογέας
/// περνά από τον [FilePickerSession]: δεύτερο κλικ εστιάζει τον ήδη ανοιχτό
/// διάλογο αντί να ανοίξει δεύτερο.
Future<String?> promptBuildingMapExportSavePath({
  required BuildContext context,
  required String sanitizedBaseName,
  required String? initialDirectoryPath,
}) async {
  final kind = await showDialog<_ExportKind>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Τύπος εξαγωγής'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: const Text('PNG (*.png)'),
            leading: const Icon(Icons.image_outlined),
            onTap: () => Navigator.pop(ctx, _ExportKind.png),
          ),
          ListTile(
            title: const Text('JPEG (*.jpg, *.jpeg)'),
            leading: const Icon(Icons.photo_outlined),
            onTap: () => Navigator.pop(ctx, _ExportKind.jpeg),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Άκυρο'),
        ),
      ],
    ),
  );
  if (!context.mounted || kind == null) return null;

  final initialDir =
      initialDirectoryPath ?? initialDirectoryForFilePicker(null);
  final ext = kind == _ExportKind.png ? 'png' : 'jpg';
  final suggested = '$sanitizedBaseName.$ext';

  final session = await FilePickerSession.run(
    () async => FilePicker.saveFile(
      dialogTitle: 'Εξαγωγή χάρτη ορόφου',
      fileName: suggested,
      initialDirectory: initialDir,
      type: FileType.custom,
      allowedExtensions: kind == _ExportKind.png
          ? const ['png']
          : const ['jpg'],
      bytes: Uint8List(0),
    ),
  );
  // Το δεύτερο κλικ εστίασε τον ήδη ανοιχτό διάλογο — καμία νέα διαδρομή.
  if (session.refocusedExisting) return null;
  return session.value?.toFilePath();
}
