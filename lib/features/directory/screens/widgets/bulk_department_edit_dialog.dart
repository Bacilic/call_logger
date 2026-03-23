import 'package:flutter/material.dart';

import '../../../../core/utils/spell_check.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import 'department_color_palette.dart';

/// Μαζική επεξεργασία τμημάτων (κτίριο, χρώμα, σημειώσεις).
/// Η εγγραφή στη βάση γίνεται μόνο με το κουμπί «Αποθήκευση» (ενεργό μόνο αν έχει αλλάξει κάτι).
class BulkDepartmentEditDialog extends StatefulWidget {
  const BulkDepartmentEditDialog({
    super.key,
    required this.selectedDepartments,
    required this.notifier,
  });

  final List<DepartmentModel> selectedDepartments;
  final DepartmentDirectoryNotifier notifier;

  @override
  State<BulkDepartmentEditDialog> createState() =>
      _BulkDepartmentEditDialogState();
}

class _BulkDepartmentEditDialogState extends State<BulkDepartmentEditDialog> {
  static const _fieldKeys = ['building', 'color', 'notes'];

  static const _conflictHint =
      'Διαφορετικές τιμές — Η αλλαγή θα επηρεάσει όλα τα επιλεγμένα τμήματα.';

  /// Πλάτος σώματος dialog: ~ίσο με τύλιγμα του `_conflictHint` στα 276dp + περιθώριο πεδίων.
  static double _dialogBodyWidth() => 276.0 + 24.0;

  final Map<String, TextEditingController> _controllers = {};
  late Color _bulkPaletteColor;

  /// Στιγμιότυπο αρχικών τιμών φόρμας (για εντοπισμό αλλαγών).
  late String _snapBuilding;
  late String _snapNotes;
  late Color _snapColor;

  @override
  void initState() {
    super.initState();
    for (final key in _fieldKeys) {
      _controllers[key] = TextEditingController(text: _commonValue(key));
    }
    _bulkPaletteColor =
        tryParseDepartmentHex(_controllers['color']!.text.trim()) ??
        const Color(0xFF1976D2);
    _controllers['color']!.text = colorToDepartmentHex(_bulkPaletteColor);

    _snapBuilding = _controllers['building']!.text;
    _snapNotes = _controllers['notes']!.text;
    _snapColor = _bulkPaletteColor;
  }

  static String _normalized(String? v) => v?.trim() ?? '';

  String _commonValue(String fieldKey) {
    final list = widget.selectedDepartments;
    if (list.isEmpty) return '';
    final getter = _getterFor(fieldKey);
    final firstNorm = _normalized(getter(list.first));
    final allSame = list.every((d) => _normalized(getter(d)) == firstNorm);
    if (allSame) return firstNorm;
    return '';
  }

  String? Function(DepartmentModel) _getterFor(String fieldKey) {
    switch (fieldKey) {
      case 'building':
        return (d) => d.building;
      case 'color':
        return (d) => d.color;
      case 'notes':
        return (d) => d.notes;
      default:
        return (d) => null;
    }
  }

  bool _hasDifferentValues(String fieldKey) {
    final list = widget.selectedDepartments;
    if (list.length <= 1) return false;
    final getter = _getterFor(fieldKey);
    final firstNorm = _normalized(getter(list.first));
    return !list.every((d) => _normalized(getter(d)) == firstNorm);
  }

  bool get _isDirty {
    final b = _controllers['building']!.text.trim();
    final n = _controllers['notes']!.text.trim();
    final snapB = _snapBuilding.trim();
    final snapN = _snapNotes.trim();
    final colorChanged =
        colorToDepartmentHex(_bulkPaletteColor) !=
        colorToDepartmentHex(_snapColor);
    return b != snapB || n != snapN || colorChanged;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isDirty) return;
    final ids = widget.selectedDepartments
        .map((d) => d.id)
        .whereType<int>()
        .toList();
    if (ids.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final building = _controllers['building']!.text.trim();
    final notes = _controllers['notes']!.text.trim();
    final changes = <String, dynamic>{
      'building': building.isEmpty ? null : building,
      'color': colorToDepartmentHex(_bulkPaletteColor),
      'notes': notes.isEmpty ? null : notes,
    };
    await widget.notifier.bulkUpdate(ids, changes);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ενημερώθηκαν ${ids.length} τμήματα.'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Αναίρεση',
          onPressed: () async {
            await widget.notifier.undoLastBulkUpdate();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = {
      'building': 'Κτίριο',
      'color': 'Χρώμα',
      'notes': 'Σημειώσεις',
    };
    final theme = Theme.of(context);
    final outlineColor = theme.colorScheme.outline;
    final bodyW = _dialogBodyWidth();
    return AlertDialog(
      constraints: BoxConstraints(maxWidth: bodyW + 72),
      title: Text(
        'Μαζική επεξεργασία (${widget.selectedDepartments.length} τμήματα)',
      ),
      content: SizedBox(
        width: bodyW,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _fieldKeys.length; i++) ...[
                if (_fieldKeys[i] == 'color') ...[
                  Text(labels['color']!, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: outlineColor),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(4),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_hasDifferentValues('color'))
                            Text(
                              _conflictHint,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (_hasDifferentValues('color'))
                            const SizedBox(height: 8),
                          DepartmentColorPalette(
                            showHeading: false,
                            compact: true,
                            selected: _bulkPaletteColor,
                            onColorSelected: (c) {
                              setState(() {
                                _bulkPaletteColor = c;
                                _controllers['color']!.text =
                                    colorToDepartmentHex(c);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  TextFormField(
                    controller: _controllers[_fieldKeys[i]],
                    decoration: InputDecoration(
                      labelText: labels[_fieldKeys[i]],
                      hintText: _hasDifferentValues(_fieldKeys[i])
                          ? _conflictHint
                          : null,
                      hintMaxLines: 4,
                      alignLabelWithHint: _fieldKeys[i] == 'notes',
                      border: const OutlineInputBorder(),
                    ),
                    spellCheckConfiguration: platformSpellCheckConfiguration,
                    maxLines: _fieldKeys[i] == 'notes' ? 3 : 1,
                    onChanged: (_) => setState(() {}),
                  ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _isDirty ? _save : null,
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
