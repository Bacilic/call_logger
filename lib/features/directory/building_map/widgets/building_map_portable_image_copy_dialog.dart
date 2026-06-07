import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/windows_file_name_validation.dart';

/// Αποτέλεσμα διαλόγου μεταφοράς εικόνας στο `maps_images/`.
class PortableImageCopyDialogResult {
  const PortableImageCopyDialogResult._({
    required this.copyToPortable,
    this.fileName,
  });

  /// Αντιγραφή στο `maps_images/` με το [fileName].
  const PortableImageCopyDialogResult.transfer({required String fileName})
      : this._(copyToPortable: true, fileName: fileName);

  /// Χρήση της εξωτερικής διαδρομής χωρίς αντιγραφή.
  const PortableImageCopyDialogResult.useExternalPath()
      : this._(copyToPortable: false);

  final bool copyToPortable;
  final String? fileName;
}

Future<PortableImageCopyDialogResult?> showBuildingMapPortableImageCopyDialog(
  BuildContext context, {
  required String sourceImagePath,
}) {
  return showDialog<PortableImageCopyDialogResult>(
    context: context,
    builder: (ctx) => _BuildingMapPortableImageCopyDialog(
      sourceImagePath: sourceImagePath,
    ),
  );
}

class _BuildingMapPortableImageCopyDialog extends StatefulWidget {
  const _BuildingMapPortableImageCopyDialog({required this.sourceImagePath});

  final String sourceImagePath;

  @override
  State<_BuildingMapPortableImageCopyDialog> createState() =>
      _BuildingMapPortableImageCopyDialogState();
}

class _BuildingMapPortableImageCopyDialogState
    extends State<_BuildingMapPortableImageCopyDialog> {
  late final String _originalFileName;
  late final String _originalExtension;
  late final TextEditingController _renameController;

  bool _keepOriginalName = true;
  bool _useRename = false;
  String? _validationError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final normalized = p.basename(widget.sourceImagePath.replaceAll('\\', '/'));
    _originalFileName = normalized;
    _originalExtension = normalizeImageFileExtension(p.extension(normalized));
    _renameController = TextEditingController(
      text: p.basenameWithoutExtension(normalized),
    );
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  void _setKeepOriginalName(bool value) {
    setState(() {
      _keepOriginalName = value;
      _useRename = !value;
      _validationError = null;
    });
  }

  void _setUseRename(bool value) {
    setState(() {
      _useRename = value;
      _keepOriginalName = !value;
      _validationError = null;
    });
  }

  String _resolvedFileName() {
    if (_keepOriginalName) return _originalFileName;
    return resolveImageTargetFileName(
      userInput: _renameController.text,
      originalExtension: _originalExtension,
    );
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _validationError = null;
    });

    final fileName = _resolvedFileName();
    final validationError = validateWindowsFileName(fileName);
    if (validationError != null) {
      setState(() {
        _submitting = false;
        _validationError = validationError;
      });
      return;
    }

    final destPath = p.join(AppConfig.portableMapsDirectory, fileName);
    if (await File(destPath).exists()) {
      setState(() {
        _submitting = false;
        _validationError = 'Υπάρχει ήδη αρχείο με το όνομα «$fileName» στο maps_images.';
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(
      context,
      PortableImageCopyDialogResult.transfer(fileName: fileName),
    );
  }

  void _useExternalPath() {
    if (_submitting) return;
    Navigator.pop(context, const PortableImageCopyDialogResult.useExternalPath());
  }

  @override
  Widget build(BuildContext context) {
    final renameHint = _originalExtension == '.png' || _originalExtension == '.jpg'
        ? 'π.χ. ${p.basenameWithoutExtension(_originalFileName)}'
        : 'π.χ. plan_${p.basenameWithoutExtension(_originalFileName)}';

    return AlertDialog(
      title: const Text('Μεταφορά εικόνας για φορητότητα'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Η επιλεγμένη εικόνα βρίσκεται εκτός του φακέλου της εφαρμογής.\n'
              'Μπορείτε να την αντιγράψετε στο maps_images δίπλα στο εκτελέσιμο '
              'ή να τη χρησιμοποιήσετε από την τρέχουσα θέση της (χωρίς μεταφορά).',
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _keepOriginalName,
              onChanged: _submitting ? null : (v) => _setKeepOriginalName(v ?? false),
              title: Text('Διατήρηση ονόματος «$_originalFileName»'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _useRename,
              onChanged: _submitting ? null : (v) => _setUseRename(v ?? false),
              title: const Text('Μετονομασία σε:'),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: TextField(
                controller: _renameController,
                enabled: _useRename && !_submitting,
                decoration: InputDecoration(
                  hintText: renameHint,
                  helperText: _useRename
                      ? 'Αν παραλείψετε την κατάληξη, θα χρησιμοποιηθεί $_originalExtension.'
                      : null,
                  errorText: _useRename ? _validationError : null,
                ),
                onChanged: (_) {
                  if (_validationError != null) {
                    setState(() => _validationError = null);
                  }
                },
              ),
            ),
            if (_keepOriginalName && _validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Άκυρο'),
        ),
        TextButton(
          onPressed: _submitting ? null : _useExternalPath,
          child: const Text('Χωρίς μεταφορά'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _confirm,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Μεταφορά'),
        ),
      ],
    );
  }
}
