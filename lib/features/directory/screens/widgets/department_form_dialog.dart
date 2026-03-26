import 'package:flutter/material.dart';

import '../../../../core/errors/department_exists_exception.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../../../core/utils/spell_check.dart';
import '../../../../core/widgets/lexicon_spell_text_form_field.dart';
import '../../../../core/widgets/spell_check_controller.dart';
import '../../models/department_model.dart';
import '../../providers/department_directory_provider.dart';
import 'department_color_palette.dart';

enum _ConflictResolutionChoice { moveToDepartment, keepCurrentOwnership }

class _SharedConflictItem {
  _SharedConflictItem({
    required this.key,
    required this.value,
    required this.isPhone,
    required this.ownerDetails,
    required this.sourceForMoveText,
  });

  final String key;
  final String value;
  final bool isPhone;
  final String ownerDetails;
  final String sourceForMoveText;
}

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
  late final SpellCheckController _notesController;
  late final TextEditingController _hexController;
  late final TextEditingController _sharedPhoneInputController;
  late final TextEditingController _sharedEquipmentInputController;

  late Color _selectedColor;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _buildingFocus = FocusNode();
  final FocusNode _colorFocus = FocusNode();
  final FocusNode _notesFocus = FocusNode();
  final FocusNode _sharedPhoneInputFocus = FocusNode();
  final FocusNode _sharedEquipmentInputFocus = FocusNode();
  bool _isNormalizingDelimitedInput = false;

  List<String> _sharedPhones = [];
  List<String> _sharedEquipmentCodes = [];
  late final String _snapName;
  late final String _snapBuilding;
  late final String _snapNotes;
  late final String _snapColorHex;
  late final List<String> _snapSharedPhones;
  late final List<String> _snapSharedEquipmentCodes;

  bool get _isEdit =>
      widget.initialDepartment != null && !widget.isClone;

  bool get _isDirty {
    if (_nameController.text.trim() != _snapName) return true;
    if (_buildingController.text.trim() != _snapBuilding) return true;
    if (_notesController.text.trim() != _snapNotes) return true;
    final parsedHex = tryParseDepartmentHex(_hexController.text.trim());
    final effectiveHex = colorToDepartmentHex(parsedHex ?? _selectedColor);
    if (effectiveHex != _snapColorHex) return true;

    final currentPhones = _sharedPhones
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    final currentEquipment = _sharedEquipmentCodes
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    if (currentPhones.join('|') != _snapSharedPhones.join('|')) return true;
    if (currentEquipment.join('|') != _snapSharedEquipmentCodes.join('|')) {
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    final d = widget.initialDepartment;
    _nameController = TextEditingController(text: d?.name ?? '');
    _buildingController = TextEditingController(text: d?.building ?? '');
    _notesController = SpellCheckController()..text = (d?.notes ?? '');
    _selectedColor =
        tryParseDepartmentHex(d?.color) ?? const Color(0xFF1976D2);
    _hexController = TextEditingController(
      text: colorToDepartmentHex(_selectedColor),
    );
    _sharedPhoneInputController = TextEditingController();
    _sharedEquipmentInputController = TextEditingController();
    final did = d?.id;
    if (did != null) {
      _sharedPhones = LookupService.instance.getDirectPhonesByDepartment(did);
      _sharedEquipmentCodes =
          LookupService.instance.getSharedEquipmentCodesByDepartment(did);
    }
    _snapName = _nameController.text.trim();
    _snapBuilding = _buildingController.text.trim();
    _snapNotes = _notesController.text.trim();
    _snapColorHex = colorToDepartmentHex(_selectedColor);
    _snapSharedPhones = _sharedPhones
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    _snapSharedEquipmentCodes = _sharedEquipmentCodes
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    _nameController.addListener(_onFieldChanged);
    _buildingController.addListener(_onFieldChanged);
    _notesController.addListener(_onFieldChanged);
    _hexController.addListener(_onFieldChanged);
    _sharedPhoneInputFocus.addListener(_onSharedPhoneFocusChanged);
    _sharedEquipmentInputFocus.addListener(_onSharedEquipmentFocusChanged);
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
        case 'phones':
          _sharedPhoneInputFocus.requestFocus();
          break;
        case 'equipment':
          _sharedEquipmentInputFocus.requestFocus();
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
    _nameController.removeListener(_onFieldChanged);
    _buildingController.removeListener(_onFieldChanged);
    _notesController.removeListener(_onFieldChanged);
    _hexController.removeListener(_onFieldChanged);
    _sharedPhoneInputFocus.removeListener(_onSharedPhoneFocusChanged);
    _sharedEquipmentInputFocus.removeListener(_onSharedEquipmentFocusChanged);
    _nameController.dispose();
    _buildingController.dispose();
    _hexController.dispose();
    _sharedPhoneInputController.dispose();
    _sharedEquipmentInputController.dispose();
    _notesController.dispose();
    _nameFocus.dispose();
    _buildingFocus.dispose();
    _colorFocus.dispose();
    _notesFocus.dispose();
    _sharedPhoneInputFocus.dispose();
    _sharedEquipmentInputFocus.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  void _onSharedPhoneFocusChanged() {
    if (!_sharedPhoneInputFocus.hasFocus) {
      _commitDelimitedInput(
        controller: _sharedPhoneInputController,
        target: _sharedPhones,
        keepLastIncomplete: false,
      );
    }
  }

  void _onSharedEquipmentFocusChanged() {
    if (!_sharedEquipmentInputFocus.hasFocus) {
      _commitDelimitedInput(
        controller: _sharedEquipmentInputController,
        target: _sharedEquipmentCodes,
        keepLastIncomplete: false,
      );
    }
  }

  void _commitDelimitedInput({
    required TextEditingController controller,
    required List<String> target,
    required bool keepLastIncomplete,
  }) {
    if (_isNormalizingDelimitedInput) return;
    final raw = controller.text;
    if (raw.trim().isEmpty) return;
    final hasDelimiter = raw.contains(',') || raw.contains(RegExp(r'\s'));
    if (!hasDelimiter && keepLastIncomplete) return;

    final endsWithDelimiter = RegExp(r'[,\s]$').hasMatch(raw);
    final pieces = raw
        .split(RegExp(r'[,\s]+'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (pieces.isEmpty) return;

    final commitCount =
        (!keepLastIncomplete || endsWithDelimiter) ? pieces.length : pieces.length - 1;
    if (commitCount <= 0) return;
    final toCommit = pieces.take(commitCount);
    final remainder = (keepLastIncomplete && !endsWithDelimiter)
        ? pieces.last
        : '';

    _isNormalizingDelimitedInput = true;
    setState(() {
      final set = target.toSet()..addAll(toCommit);
      target
        ..clear()
        ..addAll(set.toList()..sort((a, b) => a.compareTo(b)));
      controller.text = remainder;
      controller.selection = TextSelection.collapsed(offset: remainder.length);
    });
    _isNormalizingDelimitedInput = false;
  }

  static List<String> _splitCommaSeparated(String raw) {
    return raw
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
  }

  Future<({
    List<String> acceptedPhones,
    List<String> acceptedEquipmentCodes,
    Set<String> phonesToMoveFromUsers,
    Set<String> equipmentToMoveFromUsers,
  })?> _resolveCrossUsageConflicts(
    int? departmentId,
    String targetDepartmentName,
    List<String> sharedPhones,
    List<String> sharedEquipmentCodes,
  ) async {
    final lookup = LookupService.instance;
    final conflicts = <_SharedConflictItem>[];

    for (final phone in sharedPhones) {
      final usage = lookup.checkPhoneUsage(phone);
      final hasDeptConflict = usage.departmentId != null &&
          (departmentId == null || usage.departmentId != departmentId);
      if (usage.hasUserOwners || hasDeptConflict) {
        final owners = lookup.findUsersByPhone(phone);
        final ownerLabels = owners
            .map((u) {
              final full = (u.name ?? '').trim();
              if (full.isEmpty) return '';
              final dep = (u.departmentName ?? '').trim();
              if (dep.isEmpty) return full;
              return '$full ($dep)';
            })
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
        final detailsParts = <String>[];
        if (ownerLabels.isNotEmpty) {
          detailsParts.add('Ονοματεπώνυμο: ${ownerLabels.join(', ')}');
        }
        if (hasDeptConflict) {
          detailsParts.add('Τμήμα: ${usage.departmentName ?? usage.departmentId}');
        }
        final source = hasDeptConflict
            ? (usage.departmentName ?? '${usage.departmentId}')
            : (ownerLabels.isNotEmpty ? ownerLabels.join(', ') : 'άλλη συσχέτιση');
        conflicts.add(
          _SharedConflictItem(
            key: 'phone::$phone',
            value: phone,
            isPhone: true,
            ownerDetails: detailsParts.join(' | '),
            sourceForMoveText: source,
          ),
        );
      }
    }
    for (final code in sharedEquipmentCodes) {
      final usage = lookup.checkEquipmentUsage(code);
      final hasDeptConflict = usage.departmentId != null &&
          (departmentId == null || usage.departmentId != departmentId);
      if (usage.hasUserOwners || hasDeptConflict) {
        final ownerLabels = <String>{};
        final matches = lookup.findEquipmentsByCode(code);
        for (final e in matches) {
          if ((e.code ?? '').trim() != code) continue;
          final eid = e.id;
          if (eid == null) continue;
          for (final u in lookup.findUsersForEquipment(eid)) {
            final full = (u.name ?? '').trim();
            if (full.isEmpty) continue;
            final dep = (u.departmentName ?? '').trim();
            ownerLabels.add(dep.isEmpty ? full : '$full ($dep)');
          }
        }
        final ownerList = ownerLabels.toList()..sort((a, b) => a.compareTo(b));
        final detailsParts = <String>[];
        if (ownerList.isNotEmpty) {
          detailsParts.add('Ονοματεπώνυμο: ${ownerList.join(', ')}');
        }
        if (hasDeptConflict) {
          detailsParts.add('Τμήμα: ${usage.departmentName ?? usage.departmentId}');
        }
        final source = hasDeptConflict
            ? (usage.departmentName ?? '${usage.departmentId}')
            : (ownerList.isNotEmpty ? ownerList.join(', ') : 'άλλη συσχέτιση');
        conflicts.add(
          _SharedConflictItem(
            key: 'equipment::$code',
            value: code,
            isPhone: false,
            ownerDetails: detailsParts.join(' | '),
            sourceForMoveText: source,
          ),
        );
      }
    }
    if (conflicts.isEmpty) {
      return (
        acceptedPhones: sharedPhones,
        acceptedEquipmentCodes: sharedEquipmentCodes,
        phonesToMoveFromUsers: <String>{},
        equipmentToMoveFromUsers: <String>{},
      );
    }

    final decisions = <String, _ConflictResolutionChoice>{};
    final result = await showDialog<Map<String, _ConflictResolutionChoice>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final allResolved = decisions.length == conflicts.length;
          final desiredHeight =
              (conflicts.length * 132.0).clamp(220.0, 520.0).toDouble();
          return AlertDialog(
            title: const Text('Εκκρεμή τηλέφωνα / εξοπλισμοί'),
            content: SizedBox(
              width: 680,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: desiredHeight),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Για κάθε στοιχείο επίλεξε αν θα μεταφερθεί στο τμήμα ή αν θα παραμείνει στην τωρινή του συσχέτιση.',
                      ),
                      const SizedBox(height: 10),
                      for (final item in conflicts) ...[
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.isPhone ? 'Τηλέφωνο' : 'Εξοπλισμός'}: ${item.value}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(item.ownerDetails),
                                RadioGroup<_ConflictResolutionChoice>(
                                  groupValue: decisions[item.key],
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setDialogState(() {
                                      decisions[item.key] = v;
                                    });
                                  },
                                  child: Column(
                                    children: [
                                      RadioListTile<_ConflictResolutionChoice>(
                                        dense: true,
                                        value: _ConflictResolutionChoice
                                            .moveToDepartment,
                                        title: Text(
                                          'Μεταφορά στο τμήμα «$targetDepartmentName» (αφαίρεση από «${item.sourceForMoveText}»)',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const RadioListTile<
                                          _ConflictResolutionChoice>(
                                        dense: true,
                                        value: _ConflictResolutionChoice
                                            .keepCurrentOwnership,
                                        title: Text(
                                          'Να μην προστεθεί στο τμήμα (παραμονή στην τωρινή συσχέτιση)',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Άκυρο'),
              ),
              FilledButton(
                onPressed: allResolved
                    ? () => Navigator.of(ctx).pop(
                          Map<String, _ConflictResolutionChoice>.from(decisions),
                        )
                    : null,
                child: const Text('Επιβεβαίωση'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return null;
    final acceptedPhones = <String>[];
    final acceptedEquipment = <String>[];
    final phonesToMoveFromUsers = <String>{};
    final equipmentToMoveFromUsers = <String>{};
    for (final phone in sharedPhones) {
      final key = 'phone::$phone';
      final decision = result[key];
      if (decision == null) continue;
      if (decision == _ConflictResolutionChoice.moveToDepartment) {
        acceptedPhones.add(phone);
        phonesToMoveFromUsers.add(phone);
      }
    }
    for (final code in sharedEquipmentCodes) {
      final key = 'equipment::$code';
      final decision = result[key];
      if (decision == null) continue;
      if (decision == _ConflictResolutionChoice.moveToDepartment) {
        acceptedEquipment.add(code);
        equipmentToMoveFromUsers.add(code);
      }
    }
    return (
      acceptedPhones: acceptedPhones,
      acceptedEquipmentCodes: acceptedEquipment,
      phonesToMoveFromUsers: phonesToMoveFromUsers,
      equipmentToMoveFromUsers: equipmentToMoveFromUsers,
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final building = _buildingController.text.trim();
    final parsedHex = tryParseDepartmentHex(_hexController.text.trim());
    final color = colorToDepartmentHex(parsedHex ?? _selectedColor);
    final notes = _notesController.text.trim();
    var sharedPhones = _sharedPhones
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    var sharedEquipmentCodes = _sharedEquipmentCodes
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    var phonesToMoveFromUsers = <String>{};
    var equipmentToMoveFromUsers = <String>{};

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
        final did = model.id;
        if (did != null) {
          final resolved = await _resolveCrossUsageConflicts(
            did,
            name,
            sharedPhones,
            sharedEquipmentCodes,
          );
          if (resolved == null) return;
          sharedPhones = resolved.acceptedPhones;
          sharedEquipmentCodes = resolved.acceptedEquipmentCodes;
          phonesToMoveFromUsers = resolved.phonesToMoveFromUsers;
          equipmentToMoveFromUsers = resolved.equipmentToMoveFromUsers;
        }
        await widget.notifier.updateDepartment(model);
        if (did != null) {
          await widget.notifier.updateDepartmentSharedAssets(
            did,
            sharedPhones: sharedPhones,
            sharedEquipmentCodes: sharedEquipmentCodes,
            phonesToMoveFromUsers: phonesToMoveFromUsers,
            equipmentToMoveFromUsers: equipmentToMoveFromUsers,
          );
        }
      } else {
        final resolved = await _resolveCrossUsageConflicts(
          null,
          name,
          sharedPhones,
          sharedEquipmentCodes,
        );
        if (resolved == null) return;
        sharedPhones = resolved.acceptedPhones;
        sharedEquipmentCodes = resolved.acceptedEquipmentCodes;
        phonesToMoveFromUsers = resolved.phonesToMoveFromUsers;
        equipmentToMoveFromUsers = resolved.equipmentToMoveFromUsers;
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
        final did = await DatabaseHelper.instance.getOrCreateDepartmentIdByName(
          name,
        );
        if (did != null) {
          await widget.notifier.updateDepartmentSharedAssets(
            did,
            sharedPhones: sharedPhones,
            sharedEquipmentCodes: sharedEquipmentCodes,
            phonesToMoveFromUsers: phonesToMoveFromUsers,
            equipmentToMoveFromUsers: equipmentToMoveFromUsers,
          );
        }
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

  void _addSharedPhonesFromInput(String raw) {
    final incoming = _splitCommaSeparated(raw);
    if (incoming.isEmpty) return;
    setState(() {
      final set = _sharedPhones.toSet();
      for (final v in incoming) {
        set.add(v);
      }
      _sharedPhones = set.toList()..sort((a, b) => a.compareTo(b));
      _sharedPhoneInputController.clear();
    });
  }

  void _addSharedEquipmentFromInput(String raw) {
    final incoming = _splitCommaSeparated(raw);
    if (incoming.isEmpty) return;
    setState(() {
      final set = _sharedEquipmentCodes.toSet();
      for (final v in incoming) {
        set.add(v);
      }
      _sharedEquipmentCodes = set.toList()..sort((a, b) => a.compareTo(b));
      _sharedEquipmentInputController.clear();
    });
  }

  Widget _buildReadOnlyLegend({
    required BuildContext context,
    required String title,
    required Map<String, List<String>> byValueToOwners,
  }) {
    if (byValueToOwners.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final key in byValueToOwners.keys)
              Tooltip(
                message: byValueToOwners[key]!.join(', '),
                child: Chip(
                  label: Text(key),
                  avatar: const Icon(Icons.person, size: 14),
                ),
              ),
          ],
        ),
      ],
    );
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
                Text(
                  'Κοινόχρηστα τηλέφωνα',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                RawAutocomplete<String>(
                  textEditingController: _sharedPhoneInputController,
                  focusNode: _sharedPhoneInputFocus,
                  optionsBuilder: (value) {
                    final q = SearchTextNormalizer.normalizeForSearch(value.text);
                    final all = LookupService.instance.getAllKnownPhones();
                    if (q.isEmpty) return all;
                    return all.where(
                      (v) => SearchTextNormalizer.matchesNormalizedQuery(v, q),
                    );
                  },
                  displayStringForOption: (v) => v,
                  onSelected: (v) => _addSharedPhonesFromInput(v),
                  fieldViewBuilder: (context, controller, focusNode, _) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Προσθήκη τηλεφώνων (με κόμμα)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _commitDelimitedInput(
                        controller: _sharedPhoneInputController,
                        target: _sharedPhones,
                        keepLastIncomplete: true,
                      ),
                      onSubmitted: _addSharedPhonesFromInput,
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 380,
                            maxHeight: 200,
                          ),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            children: [
                              for (final opt in options)
                                ListTile(
                                  dense: true,
                                  title: Text(opt),
                                  onTap: () => onSelected(opt),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in _sharedPhones)
                      InputChip(
                        label: Text(p),
                        backgroundColor: _snapSharedPhones.contains(p)
                            ? null
                            : Colors.lightGreen.shade100,
                        onDeleted: () => setState(() {
                          _sharedPhones.remove(p);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (widget.initialDepartment?.id != null)
                  _buildReadOnlyLegend(
                    context: context,
                    title:
                        'Τηλέφωνα καλούντων (μόνο προβολή - tooltip με καλούντα)',
                    byValueToOwners: LookupService.instance
                        .getCallerOwnedPhonesByDepartment(
                      widget.initialDepartment!.id!,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Κοινόχρηστος εξοπλισμός',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                RawAutocomplete<String>(
                  textEditingController: _sharedEquipmentInputController,
                  focusNode: _sharedEquipmentInputFocus,
                  optionsBuilder: (value) {
                    final q = SearchTextNormalizer.normalizeForSearch(value.text);
                    final all = LookupService.instance.getAllKnownEquipmentCodes();
                    if (q.isEmpty) return all;
                    return all.where(
                      (v) => SearchTextNormalizer.matchesNormalizedQuery(v, q),
                    );
                  },
                  displayStringForOption: (v) => v,
                  onSelected: (v) => _addSharedEquipmentFromInput(v),
                  fieldViewBuilder: (context, controller, focusNode, _) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Προσθήκη εξοπλισμού (με κόμμα)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _commitDelimitedInput(
                        controller: _sharedEquipmentInputController,
                        target: _sharedEquipmentCodes,
                        keepLastIncomplete: true,
                      ),
                      onSubmitted: _addSharedEquipmentFromInput,
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 380,
                            maxHeight: 200,
                          ),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            children: [
                              for (final opt in options)
                                ListTile(
                                  dense: true,
                                  title: Text(opt),
                                  onTap: () => onSelected(opt),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final code in _sharedEquipmentCodes)
                      InputChip(
                        label: Text(code),
                        backgroundColor: _snapSharedEquipmentCodes.contains(code)
                            ? null
                            : Colors.lightGreen.shade100,
                        onDeleted: () => setState(() {
                          _sharedEquipmentCodes.remove(code);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (widget.initialDepartment?.id != null)
                  _buildReadOnlyLegend(
                    context: context,
                    title:
                        'Εξοπλισμός καλούντων (μόνο προβολή - tooltip με καλούντα)',
                    byValueToOwners: LookupService.instance
                        .getCallerOwnedEquipmentByDepartment(
                      widget.initialDepartment!.id!,
                    ),
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
                LexiconSpellTextFormField(
                  controller: _notesController,
                  focusNode: _notesFocus,
                  decoration: const InputDecoration(
                    labelText: 'Σημειώσεις',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  onChanged: (_) => _onFieldChanged(),
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
          onPressed: (_isEdit && !_isDirty) ? null : _save,
          child: Text(_isEdit ? 'Αποθήκευση' : 'Προσθήκη'),
        ),
      ],
    );
  }
}
