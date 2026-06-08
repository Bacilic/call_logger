import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
import '../../../../core/utils/search_text_normalizer.dart';
import '../../models/department_model.dart';

/// Sentinel για επιλογή «δημιουργία νέου τμήματος» στο autocomplete.
const _kCreateDepartmentOptionPrefix = '\uE000';

bool _isCreateDepartmentOption(String option) =>
    option.startsWith(_kCreateDepartmentOptionPrefix);

String _createDepartmentOptionValue(String name) =>
    '$_kCreateDepartmentOptionPrefix$name';

String _departmentOptionLabel(String option) {
  if (_isCreateDepartmentOption(option)) {
    final name = option.substring(_kCreateDepartmentOptionPrefix.length);
    return 'Δημιουργία νέου τμήματος «$name»';
  }
  return option;
}

/// Επιλογή στον κύριο διάλογο αποδέσμευσης κοινόχρηστου στοιχείου.
enum SharedAssetDisconnectChoice {
  keepInDepartment,
  transfer,
  delete,
}

/// Στόχος μεταφοράς (υπάρχον ή νέο τμήμα).
class SharedAssetTransferTarget {
  const SharedAssetTransferTarget.existing(this.departmentId)
      : newDepartmentName = null;

  const SharedAssetTransferTarget.createNew(this.newDepartmentName)
      : departmentId = null;

  final int? departmentId;
  final String? newDepartmentName;
}

/// Αποτέλεσμα ροής αποδέσμευσης για ένα στοιχείο.
class SharedAssetDisconnectItemResult {
  const SharedAssetDisconnectItemResult.keep()
      : choice = SharedAssetDisconnectChoice.keepInDepartment,
        transferTarget = null;

  const SharedAssetDisconnectItemResult.transfer(this.transferTarget)
      : choice = SharedAssetDisconnectChoice.transfer;

  const SharedAssetDisconnectItemResult.delete()
      : choice = SharedAssetDisconnectChoice.delete,
        transferTarget = null;

  final SharedAssetDisconnectChoice choice;
  final SharedAssetTransferTarget? transferTarget;
}

/// Συγκεντρωτικό αποτέλεσμα αποδέσμευσης πολλών στοιχείων.
class SharedAssetDisconnectBatchResult {
  const SharedAssetDisconnectBatchResult({
    this.phonesToKeep = const [],
    this.equipmentToKeep = const [],
    this.phoneTransfers = const {},
    this.equipmentTransfers = const {},
    this.phonesToDelete = const [],
    this.equipmentToDelete = const [],
    this.newDepartmentNamesToCreate = const {},
  });

  final List<String> phonesToKeep;
  final List<String> equipmentToKeep;
  final Map<String, SharedAssetTransferTarget> phoneTransfers;
  final Map<String, SharedAssetTransferTarget> equipmentTransfers;
  final List<String> phonesToDelete;
  final List<String> equipmentToDelete;

  /// Κλειδί: όνομα νέου τμήματος → αριθμοί τηλεφώνων που θα το λάβουν.
  final Map<String, Set<String>> newDepartmentNamesToCreate;
}

/// Ροή αποδέσμευσης κοινόχρηστων τηλεφώνων/εξοπλισμού από τμήμα.
Future<SharedAssetDisconnectBatchResult?> showSharedAssetDisconnectFlow({
  required BuildContext context,
  required int sourceDepartmentId,
  required String sourceDepartmentName,
  List<String> phones = const [],
  List<String> equipmentCodes = const [],
  required List<DepartmentModel> availableDepartments,
}) async {
  if (phones.isEmpty && equipmentCodes.isEmpty) {
    return const SharedAssetDisconnectBatchResult();
  }

  final keptPhones = <String>[];
  final keptEquipment = <String>[];
  final phoneTransfers = <String, SharedAssetTransferTarget>{};
  final equipmentTransfers = <String, SharedAssetTransferTarget>{};
  final phonesToDelete = <String>[];
  final equipmentToDelete = <String>[];
  final newDeptPhones = <String, Set<String>>{};

  for (final phone in phones) {
    if (!context.mounted) return null;
    final item = await _resolveSingleItem(
      context: context,
      isPhone: true,
      value: phone,
      sourceDepartmentId: sourceDepartmentId,
      sourceDepartmentName: sourceDepartmentName,
      availableDepartments: availableDepartments,
    );
    if (item == null) return null;
    switch (item.choice) {
      case SharedAssetDisconnectChoice.keepInDepartment:
        keptPhones.add(phone);
      case SharedAssetDisconnectChoice.transfer:
        final target = item.transferTarget;
        if (target == null) return null;
        phoneTransfers[phone] = target;
        final newName = target.newDepartmentName?.trim();
        if (newName != null && newName.isNotEmpty) {
          newDeptPhones
              .putIfAbsent(newName, () => <String>{})
              .add(phone);
        }
      case SharedAssetDisconnectChoice.delete:
        phonesToDelete.add(phone);
    }
  }

  for (final code in equipmentCodes) {
    if (!context.mounted) return null;
    final item = await _resolveSingleItem(
      context: context,
      isPhone: false,
      value: code,
      sourceDepartmentId: sourceDepartmentId,
      sourceDepartmentName: sourceDepartmentName,
      availableDepartments: availableDepartments,
    );
    if (item == null) return null;
    switch (item.choice) {
      case SharedAssetDisconnectChoice.keepInDepartment:
        keptEquipment.add(code);
      case SharedAssetDisconnectChoice.transfer:
        final target = item.transferTarget;
        if (target == null) return null;
        equipmentTransfers[code] = target;
        final newName = target.newDepartmentName?.trim();
        if (newName != null && newName.isNotEmpty) {
          newDeptPhones.putIfAbsent(newName, () => <String>{});
        }
      case SharedAssetDisconnectChoice.delete:
        equipmentToDelete.add(code);
    }
  }

  return SharedAssetDisconnectBatchResult(
    phonesToKeep: keptPhones,
    equipmentToKeep: keptEquipment,
    phoneTransfers: phoneTransfers,
    equipmentTransfers: equipmentTransfers,
    phonesToDelete: phonesToDelete,
    equipmentToDelete: equipmentToDelete,
    newDepartmentNamesToCreate: newDeptPhones,
  );
}

Future<SharedAssetDisconnectItemResult?> _resolveSingleItem({
  required BuildContext context,
  required bool isPhone,
  required String value,
  required int sourceDepartmentId,
  required String sourceDepartmentName,
  required List<DepartmentModel> availableDepartments,
}) async {
  while (true) {
    if (!context.mounted) return null;
    final choice = await showDialog<SharedAssetDisconnectChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          isPhone
              ? 'Αποδέσμευση κοινόχρηστου τηλεφώνου'
              : 'Αποδέσμευση κοινόχρηστου εξοπλισμού',
        ),
        content: Text(
          isPhone
              ? 'Το κοινόχρηστο τηλέφωνο $value πρόκειται να αποδεσμευτεί από το τμήμα «$sourceDepartmentName».\n\nΕπιλέξτε ενέργεια:'
              : 'Ο κοινόχρηστος εξοπλισμός $value πρόκειται να αποδεσμευτεί από το τμήμα «$sourceDepartmentName».\n\nΕπιλέξτε ενέργεια:',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Άκυρο'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(
              SharedAssetDisconnectChoice.keepInDepartment,
            ),
            child: const Text('Παραμονή στο ίδιο τμήμα'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(
              SharedAssetDisconnectChoice.transfer,
            ),
            child: const Text('Μεταφορά σε άλλο τμήμα'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              SharedAssetDisconnectChoice.delete,
            ),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return null;

    switch (choice) {
      case SharedAssetDisconnectChoice.keepInDepartment:
        return const SharedAssetDisconnectItemResult.keep();
      case SharedAssetDisconnectChoice.transfer:
        final target = await _showTransferDialog(
          context: context,
          isPhone: isPhone,
          value: value,
          sourceDepartmentId: sourceDepartmentId,
          availableDepartments: availableDepartments,
        );
        if (target == null) continue;
        return SharedAssetDisconnectItemResult.transfer(target);
      case SharedAssetDisconnectChoice.delete:
        final confirmed = await _confirmDelete(
          context: context,
          isPhone: isPhone,
          value: value,
        );
        if (confirmed != true) continue;
        return const SharedAssetDisconnectItemResult.delete();
    }
  }
}

Future<SharedAssetTransferTarget?> _showTransferDialog({
  required BuildContext context,
  required bool isPhone,
  required String value,
  required int sourceDepartmentId,
  required List<DepartmentModel> availableDepartments,
}) async {
  final depts = availableDepartments
      .where(
        (d) =>
            d.id != null &&
            d.id != sourceDepartmentId &&
            !d.isDeleted &&
            d.name.trim().isNotEmpty,
      )
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  return showDialog<SharedAssetTransferTarget>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SharedAssetTransferDialog(
      isPhone: isPhone,
      value: value,
      departments: depts,
    ),
  );
}

class _SharedAssetTransferDialog extends StatefulWidget {
  const _SharedAssetTransferDialog({
    required this.isPhone,
    required this.value,
    required this.departments,
  });

  final bool isPhone;
  final String value;
  final List<DepartmentModel> departments;

  @override
  State<_SharedAssetTransferDialog> createState() =>
      _SharedAssetTransferDialogState();
}

class _SharedAssetTransferDialogState extends State<_SharedAssetTransferDialog> {
  final _departmentController = TextEditingController();
  final _departmentFocus = FocusNode();

  List<String> get _departmentNames =>
      widget.departments.map((d) => d.name.trim()).where((n) => n.isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _departmentController.addListener(_onDepartmentTextChanged);
  }

  void _onDepartmentTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _departmentController.removeListener(_onDepartmentTextChanged);
    _departmentController.dispose();
    _departmentFocus.dispose();
    super.dispose();
  }

  DepartmentModel? _matchDepartment(String text) {
    final q = SearchTextNormalizer.normalizeForSearch(text.trim());
    if (q.isEmpty) return null;
    for (final d in widget.departments) {
      if (SearchTextNormalizer.normalizeForSearch(d.name) == q) return d;
    }
    return null;
  }

  Iterable<String> _departmentOptions(String query) {
    final q = SearchTextNormalizer.normalizeForSearch(query);
    final matches = q.isEmpty
        ? List<String>.from(_departmentNames)
        : _departmentNames
              .where(
                (name) => SearchTextNormalizer.matchesNormalizedQuery(name, q),
              )
              .toList();
    final typed = query.trim();
    if (typed.isNotEmpty && _matchDepartment(typed) == null) {
      matches.add(_createDepartmentOptionValue(typed));
    }
    return matches;
  }

  Future<bool> _confirmCreateDepartment(String newName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (confirmCtx) => AlertDialog(
        title: const Text('Δημιουργία νέου τμήματος'),
        content: Text(
          widget.isPhone
              ? 'Θα δημιουργηθεί νέο τμήμα: $newName με κοινόχρηστο τηλέφωνο: ${widget.value}.'
              : 'Θα δημιουργηθεί νέο τμήμα: $newName με κοινόχρηστο εξοπλισμό: ${widget.value}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmCtx).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(confirmCtx).pop(true),
            child: const Text('Επιβεβαίωση'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _submitNewDepartment(String newName) async {
    if (!await _confirmCreateDepartment(newName)) return;
    if (!mounted) return;
    Navigator.of(context).pop(
      SharedAssetTransferTarget.createNew(newName),
    );
  }

  Future<void> _submit() async {
    final text = _departmentController.text.trim();
    if (text.isEmpty) return;
    final matched = _matchDepartment(text);
    if (matched?.id != null) {
      Navigator.of(context).pop(
        SharedAssetTransferTarget.existing(matched!.id!),
      );
      return;
    }
    await _submitNewDepartment(text);
  }

  Future<void> _onDepartmentOptionSelected(String selection) async {
    if (_isCreateDepartmentOption(selection)) {
      final newName = selection.substring(_kCreateDepartmentOptionPrefix.length);
      _departmentController.text = newName;
      await _submitNewDepartment(newName);
      return;
    }
    _departmentController.text = selection;
    final matched = _matchDepartment(selection);
    if (matched?.id != null && mounted) {
      Navigator.of(context).pop(
        SharedAssetTransferTarget.existing(matched!.id!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Μεταφορά κοινόχρηστου'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isPhone
                  ? 'Τηλέφωνο: ${widget.value}'
                  : 'Εξοπλισμός: ${widget.value}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            RawAutocomplete<String>(
              textEditingController: _departmentController,
              focusNode: _departmentFocus,
              displayStringForOption: _departmentOptionLabel,
              optionsBuilder: (textEditingValue) =>
                  _departmentOptions(textEditingValue.text),
              onSelected: (selection) => _onDepartmentOptionSelected(selection),
              fieldViewBuilder: (context, controller, focusNode, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Τμήμα προορισμού',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _submit(),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final opts = options.toList();
                if (opts.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 400,
                        maxHeight: 220,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: opts.length,
                        itemBuilder: (context, index) {
                          final option = opts[index];
                          final isCreate = _isCreateDepartmentOption(option);
                          return ListTile(
                            dense: true,
                            leading: isCreate
                                ? Icon(
                                    Icons.add_circle_outline,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                            title: Text(
                              _departmentOptionLabel(option),
                              style: isCreate
                                  ? TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    )
                                  : null,
                            ),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: _departmentController.text.trim().isEmpty ? null : _submit,
          child: const Text('Μεταφορά'),
        ),
      ],
    );
  }
}

Future<bool?> _confirmDelete({
  required BuildContext context,
  required bool isPhone,
  required String value,
}) async {
  final db = await DatabaseHelper.instance.database;
  final dir = DirectoryRepository(db);
  final int refCount;
  if (isPhone) {
    final id = await dir.getPhoneIdByNumber(value);
    refCount = id == null
        ? 0
        : await dir.countPhoneReferencesExcludingAudit(id, value);
  } else {
    final id = await dir.getEquipmentIdByCode(value);
    refCount = id == null
        ? 0
        : await dir.countEquipmentReferencesExcludingAudit(id);
  }

  if (!context.mounted) return null;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(isPhone ? 'Διαγραφή τηλεφώνου' : 'Διαγραφή εξοπλισμού'),
      content: Text(
        isPhone
            ? 'Ο αριθμός $value συνδέεται με $refCount εγγραφές στη βάση. Να καταργηθεί;'
            : 'Ο εξοπλισμός $value συνδέεται με $refCount εγγραφές στη βάση. Να καταργηθεί;',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Όχι'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Ναι, κατάργηση'),
        ),
      ],
    ),
  );
}
