import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/file_picker_initial_directory.dart';

/// Διάλογος αποθήκευσης για εξαγωγή χάρτη.
///
/// Επιλογή τύπου σε [AlertDialog] και μετά `FilePicker.saveFile`
/// με ένα φίλτρο τη φορά (ώστε να μην εμφανίζονται και οι τρεις επεκτάσεις μαζί).
Future<String?> promptBuildingMapExportSavePath({
  required BuildContext context,
  required String sanitizedBaseName,
  required String? initialDirectoryPath,
}) async {
  return _promptExportSavePath(
    context: context,
    sanitizedBaseName: sanitizedBaseName,
    initialDirectoryPath: initialDirectoryPath,
  );
}

enum _ExportKind { png, jpeg }

Future<String?> _promptExportSavePath({
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

  return FilePicker.saveFile(
    dialogTitle: 'Εξαγωγή χάρτη ορόφου',
    fileName: suggested,
    initialDirectory: initialDir,
    type: FileType.custom,
    allowedExtensions: kind == _ExportKind.png ? const ['png'] : const ['jpg'],
  );
}
