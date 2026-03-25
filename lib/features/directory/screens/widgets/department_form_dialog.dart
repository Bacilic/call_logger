import 'package:flutter/material.dart';

import '../../../../core/errors/department_exists_exception.dart';
import '../../../../core/utils/spell_check.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import 'department_color_palette.dart';

/// Διάλογος προσθήκης / επεξεργασίας / αντιγράφου τμήματος.
class DepartmentFormDialog extends StatefulWidget {
  const DepartmentFormDialog({
    super.key,
    this.initialDepartment,
    required this.notifier,
    this.isClone = false,
    this.focusedField,
    this.onSaved,
  });

  final DepartmentModel? initialDepartment;
  final DepartmentDirectoryNotifier notifier;
  final bool isClone;
  final String? focusedField;
  final VoidCallback? onSaved;

  @override
  State<DepartmentFormDialog> createState() => _DepartmentFormDialogState();
}

class _DepartmentFormDialogState extends State<DepartmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _buildingController;
  late final TextEditingController _notesController;
  late final TextEditingController _hexController;

  late Color _selectedColor;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _buildingFocus = FocusNode();
  final FocusNode _colorFocus = FocusNode();
  final FocusNode _notesFocus = FocusNode();

  bool get _isEdit =>
      widget.initialDepartment != null && !widget.isClone;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDepartment;
    _nameController = TextEditingController(text: d?.name ?? '');
    _buildingController = TextEditingController(text: d?.building ?? '');
    _notesController = TextEditingController(text: d?.notes ?? '');
    _selectedColor =
        tryParseDepartmentHex(d?.color) ?? const Color(0xFF1976D2);
    _hexController = TextEditingController(
      text: colorToDepartmentHex(_selectedColor),
    );
    if (widget.isClone) {
      _nameController.text = '${d?.name ?? ''} (αντίγραφο)'.trim();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.focusedField) {
        case 'building':
          _buildingFocus.requestFocus();
          break;
        case 'color':
          _colorFocus.requestFocus();
          break;
        case 'notes':
          _notesFocus.requestFocus();
          break;
        case 'name':
        default:
          _nameFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _buildingController.dispose();
    _hexController.dispose();
    _notesController.dispose();
    _nameFocus.dispose();
    _buildingFocus.dispose();
    _colorFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final building = _buildingController.text.trim();
    final parsedHex = tryParseDepartmentHex(_hexController.text.trim());
    final color = colorToDepartmentHex(parsedHex ?? _selectedColor);
    final notes = _notesController.text.trim();

    final model = DepartmentModel(
      id: _isEdit ? widget.initialDepartment!.id : null,
      name: name,
      building: building.isEmpty ? null : building,
      color: color,
      notes: notes.isEmpty ? null : notes,
      mapFloor: widget.initialDepartment?.mapFloor,
      mapX: widget.initialDepartment?.mapX,
      mapY: widget.initialDepartment?.mapY,
      mapWidth: widget.initialDepartment?.mapWidth,
      mapHeight: widget.initialDepartment?.mapHeight,
      isDeleted: widget.initialDepartment?.isDeleted ?? false,
    );

    try {
      if (_isEdit) {
        await widget.notifier.updateDepartment(model);
      } else {
        await widget.notifier.addDepartment(
          DepartmentModel(
            id: null,
            name: name,
            building: model.building,
            color: model.color,
            notes: model.notes,
            mapFloor: model.mapFloor,
            mapX: model.mapX,
            mapY: model.mapY,
            mapWidth: model.mapWidth,
            mapHeight: model.mapHeight,
            isDeleted: false,
          ),
        );
      }
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.of(context).pop(true);
    } on DepartmentExistsException catch (e) {
      if (!mounted) return;
      if (e.isDeleted) {
        final restore = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Τμήμα ως διαγραμμένο'),
            content: const Text(
              'Υπάρχει ήδη καταχώρηση με αυτό το όνομα, σημειωμένη ως διαγραμμένη. '
              'Θέλετε να την επαναφέρετε;\n\n'
              'Τα πεδία κτίριο, χρώμα και σημειώσεις από τη φόρμα θα εφαρμοστούν μετά την επαναφορά. '
              'Αν δεν πρόκειται για το ίδιο τμήμα, πατήστε «Άκυρο» και δώστε νέο, διακριτό όνομα (π.χ. «Μαγειρείο 2026»).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Άκυρο'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Επαναφορά'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (restore == true) {
          try {
            await widget.notifier.restoreDepartmentByName(
              name,
              building: building.isEmpty ? null : building,
              color: color,
              notes: notes.isEmpty ? null : notes,
            );
            if (!mounted) return;
            widget.onSaved?.call();
            Navigator.of(context).pop(true);
          } catch (err) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$err')),
            );
          }
        }
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Όνομα σε χρήση'),
            content: const Text(
              'Υπάρχει ήδη ενεργό τμήμα με αυτό το όνομα. '
              'Η διαδικασία σταματά εδώ — δώστε ένα νέο, διακριτό όνομα (π.χ. «Μαγειρείο 2026»).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Σφάλμα: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit
        ? 'Επεξεργασία τμήματος'
        : widget.isClone
            ? 'Νέο τμήμα (αντίγραφο)'
            : 'Νέο τμήμα';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  decoration: const InputDecoration(
                    labelText: 'Όνομα',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Απαιτείται όνομα';
                    }
                    return null;
                  },
                  spellCheckConfiguration: platformSpellCheckConfiguration,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _buildingController,
                  focusNode: _buildingFocus,
                  decoration: const InputDecoration(
                    labelText: 'Κτίριο',
                    border: OutlineInputBorder(),
                  ),
                  spellCheckConfiguration: platformSpellCheckConfiguration,
                ),
                const SizedBox(height: 12),
                Text(
                  'Χρώμα',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DepartmentColorPalette(
                        compact: true,
                        showHeading: false,
                        selected: _selectedColor,
                        onColorSelected: (c) {
                          setState(() {
                            _selectedColor = c;
                            _hexController.text = colorToDepartmentHex(c);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 156,
                      child: Builder(
                        builder: (context) {
                          final rawHex = _hexController.text.trim();
                          final parsedHex = tryParseDepartmentHex(rawHex);
                          final hasInvalidHex =
                              rawHex.isNotEmpty && parsedHex == null;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _hexController,
                                focusNode: _colorFocus,
                                decoration: const InputDecoration(
                                  labelText: 'Δεκαεξαδικός (Hex)',
                                  hintText: '#RRGGBB',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: TextStyle(
                                  color: hasInvalidHex
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                                textCapitalization: TextCapitalization.characters,
                                onChanged: (_) => setState(() {}),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Εισάγετε hex χρώματος';
                                  }
                                  if (tryParseDepartmentHex(v.trim()) == null) {
                                    return 'Μη έγκυρο (π.χ. #1976D2)';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 6),
                              Container(
                                height: 22,
                                decoration: BoxDecoration(
                                  color: parsedHex ?? Colors.transparent,
                                  border: Border.all(
                                    color: hasInvalidHex
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.center,
                                child: hasInvalidHex
                                    ? Icon(
                                        Icons.error_outline,
                                        size: 14,
                                        color: Theme.of(context).colorScheme.error,
                                      )
                                    : null,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  focusNode: _notesFocus,
                  decoration: const InputDecoration(
                    labelText: 'Σημειώσεις',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  spellCheckConfiguration: platformSpellCheckConfiguration,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
        ),
      ],
    );
  }
}
