import 'package:flutter/material.dart';

import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';

/// Αποτέλεσμα του διαλόγου «Νέο φύλλο κατόψης».
class BuildingMapFloorSheetAddResult {
  const BuildingMapFloorSheetAddResult({required this.label, this.floorGroup});

  /// Ετικέτα ορόφου (trimmed, ποτέ κενή).
  final String label;

  /// Ομάδα ορόφου· null όταν το πεδίο έμεινε κενό.
  final String? floorGroup;
}

/// Διάλογος «Νέο φύλλο κατόψης»: ετικέτα + προαιρετική ομάδα ορόφου.
/// Επιστρέφει null σε ακύρωση. Η «Προσθήκη» ενεργοποιείται μόνο με μη κενή ετικέτα.
Future<BuildingMapFloorSheetAddResult?> showBuildingMapFloorSheetAddDialog(
  BuildContext context,
) {
  return showDialog<BuildingMapFloorSheetAddResult>(
    context: context,
    builder: (_) => const BuildingMapFloorSheetAddDialog(),
  );
}

class BuildingMapFloorSheetAddDialog extends StatefulWidget {
  const BuildingMapFloorSheetAddDialog({super.key});

  @override
  State<BuildingMapFloorSheetAddDialog> createState() =>
      _BuildingMapFloorSheetAddDialogState();
}

class _BuildingMapFloorSheetAddDialogState
    extends State<BuildingMapFloorSheetAddDialog> {
  final _labelCtrl = SpellCheckController();
  final _groupCtrl = SpellCheckController();
  final _labelFocus = FocusNode();

  @override
  void dispose() {
    _labelCtrl.dispose();
    _groupCtrl.dispose();
    _labelFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final group = _groupCtrl.text.trim();
    Navigator.pop(
      context,
      BuildingMapFloorSheetAddResult(
        label: _labelCtrl.text.trim(),
        floorGroup: group.isEmpty ? null : group,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Νέο φύλλο κατόψης'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              autofocus: true,
              child: LexiconSpellTextFormField(
                controller: _labelCtrl,
                focusNode: _labelFocus,
                decoration: const InputDecoration(
                  labelText: 'Ετικέτα',
                  hintText: 'π.χ. 1ος — Γραφεία',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            LexiconSpellTextFormField(
              controller: _groupCtrl,
              decoration: const InputDecoration(
                labelText: 'Ομάδα ορόφου (προαιρετικό)',
                hintText: 'π.χ. L1',
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
          onPressed: _labelCtrl.text.trim().isEmpty ? null : _submit,
          child: const Text('Προσθήκη'),
        ),
      ],
    );
  }
}
