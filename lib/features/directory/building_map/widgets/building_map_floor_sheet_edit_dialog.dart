import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/models/building_map_floor.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../models/department_model.dart';
import 'building_map_floor_edit_preview.dart';

/// Αποτέλεσμα του διαλόγου «Επεξεργασία κατόψης».
class BuildingMapFloorSheetEditResult {
  const BuildingMapFloorSheetEditResult({
    required this.label,
    required this.floorGroupRaw,
    this.pickedSrcPath,
  });

  /// Νέα ετικέτα ορόφου (trimmed, ποτέ κενή).
  final String label;

  /// Περιοχή ορόφου όπως πληκτρολογήθηκε (χωρίς trim — συμβόλαιο του update).
  final String floorGroupRaw;

  /// Διαδρομή νέας εικόνας κατόψης· null όταν δεν επιλέχθηκε νέα.
  final String? pickedSrcPath;
}

/// Επιλογέας εικόνας κατόψης — ενίεται από τον controller ώστε ο διάλογος να
/// μη γνωρίζει FilePicker/μνήμη τοποθεσίας.
typedef PickFloorSheetImagePath = Future<String?> Function();

/// Διάλογος «Επεξεργασία κατόψης»: όνομα, περιοχή, αλλαγή εικόνας με
/// προεπισκόπηση. Επιστρέφει null σε ακύρωση· η «Αποθήκευση» ενεργοποιείται
/// μόνο όταν υπάρχει πραγματική αλλαγή και μη κενό όνομα.
Future<BuildingMapFloorSheetEditResult?> showBuildingMapFloorSheetEditDialog(
  BuildContext context, {
  required BuildingMapFloor floor,
  required List<DepartmentModel> previewDepartments,
  required bool initialPreviewImageAvailable,
  required PickFloorSheetImagePath pickImagePath,
}) {
  return showDialog<BuildingMapFloorSheetEditResult>(
    context: context,
    builder: (_) => BuildingMapFloorSheetEditDialog(
      floor: floor,
      previewDepartments: previewDepartments,
      initialPreviewImageAvailable: initialPreviewImageAvailable,
      pickImagePath: pickImagePath,
    ),
  );
}

class BuildingMapFloorSheetEditDialog extends StatefulWidget {
  const BuildingMapFloorSheetEditDialog({
    super.key,
    required this.floor,
    required this.previewDepartments,
    required this.initialPreviewImageAvailable,
    required this.pickImagePath,
  });

  final BuildingMapFloor floor;
  final List<DepartmentModel> previewDepartments;
  final bool initialPreviewImageAvailable;
  final PickFloorSheetImagePath pickImagePath;

  @override
  State<BuildingMapFloorSheetEditDialog> createState() =>
      _BuildingMapFloorSheetEditDialogState();
}

class _BuildingMapFloorSheetEditDialogState
    extends State<BuildingMapFloorSheetEditDialog> {
  late final SpellCheckController _labelCtrl = SpellCheckController()
    ..text = widget.floor.label;
  late final SpellCheckController _groupCtrl = SpellCheckController()
    ..text = widget.floor.floorGroup ?? '';
  final _labelFocus = FocusNode();

  String? _pickedSrcPath;
  late bool _previewImageAvailable = widget.initialPreviewImageAvailable;
  late bool _showDepartmentsOnPreview = widget.initialPreviewImageAvailable;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _groupCtrl.dispose();
    _labelFocus.dispose();
    super.dispose();
  }

  bool get _hasSaveableChanges {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) return false;
    final group = _groupCtrl.text.trim();
    return label != widget.floor.label.trim() ||
        group != (widget.floor.floorGroup ?? '').trim() ||
        _pickedSrcPath != null;
  }

  Future<void> _pickNewImage() async {
    final srcPath = await widget.pickImagePath();
    if (srcPath == null || !mounted) return;
    setState(() {
      _pickedSrcPath = srcPath;
      _previewImageAvailable = File(srcPath).existsSync();
      if (_previewImageAvailable) {
        _showDepartmentsOnPreview = true;
      }
    });
  }

  void _submit() {
    Navigator.pop(
      context,
      BuildingMapFloorSheetEditResult(
        label: _labelCtrl.text.trim(),
        floorGroupRaw: _groupCtrl.text,
        pickedSrcPath: _pickedSrcPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Επεξεργασία κατόψης'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              autofocus: true,
              child: LexiconSpellTextFormField(
                controller: _labelCtrl,
                focusNode: _labelFocus,
                decoration: const InputDecoration(labelText: 'Όνομα ορόφου'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            LexiconSpellTextFormField(
              controller: _groupCtrl,
              decoration: const InputDecoration(
                labelText: 'Περιοχή ορόφου (προαιρετικό)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickNewImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                _pickedSrcPath != null
                    ? 'Επιλέχθηκε νέα κατόψη'
                    : 'Αλλαγή κατόψης',
              ),
            ),
            const SizedBox(height: 12),
            BuildingMapFloorEditPreview(
              imagePath: _pickedSrcPath ?? widget.floor.imagePath,
              floorId: widget.floor.id,
              rotationDegrees: widget.floor.rotationDegrees,
              showDepartments: _showDepartmentsOnPreview,
              departments: widget.previewDepartments,
            ),
            Tooltip(
              message:
                  'Η προβολή τμημάτων είναι μόνο για την εκκαθάριση της '
                  'μικρογραφίας. ΔΕΝ επιρεάζει τη βασική σχεδίαση του ορόφου.',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Προβολή τμημάτων'),
                value: _showDepartmentsOnPreview,
                onChanged: _previewImageAvailable
                    ? (v) => setState(() => _showDepartmentsOnPreview = v)
                    : null,
              ),
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
          onPressed: _hasSaveableChanges ? _submit : null,
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
