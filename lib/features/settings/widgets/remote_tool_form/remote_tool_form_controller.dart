import 'package:flutter/material.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/models/remote_tool_role.dart';
import '../../../../core/services/remote_launcher_service.dart';
import '../../../../core/widgets/spell_check_controller.dart';

/// Μία γραμμή ορίσματος στη φόρμα εργαλείου.
class RemoteToolArgRow {
  RemoteToolArgRow({
    required this.stableId,
    required this.valueC,
    required this.descC,
    required this.active,
    required this.valueFocus,
    required this.descFocus,
  });

  final int stableId;
  final TextEditingController valueC;
  final SpellCheckController descC;
  final FocusNode valueFocus;
  final FocusNode descFocus;
  bool active;

  void dispose() {
    valueFocus.dispose();
    descFocus.dispose();
    valueC.dispose();
    descC.dispose();
  }
}

/// Κατάσταση και καθαρή λογική φόρμας εργαλείου (χωρίς UI).
class RemoteToolFormController extends ChangeNotifier {
  RemoteToolFormController({RemoteTool? initialTool}) : initialTool = initialTool {
    final t = initialTool;
    nameC = TextEditingController(text: t?.name ?? '');
    pathC = TextEditingController(text: t?.executablePath ?? '');
    iconC = TextEditingController(text: t?.iconAssetKey ?? '');
    _initialSortOrder = t?.sortOrder ?? 0;
    role = t?.role ?? ToolRole.generic;
    _suggestedValuesJson = t?.suggestedValuesJson;
    testIpC = TextEditingController(text: t?.testTargetIp ?? '');
    launchMode = t?.launchMode ?? 'direct_exec';
    isActive = t?.isActive ?? true;
    if (t != null && t.arguments.isNotEmpty) {
      for (final a in t.arguments) {
        argRows.add(
          createArgRow(
            stableId: nextArgId++,
            value: a.value,
            desc: a.description,
            active: a.isActive,
          ),
        );
      }
    }
    initialFormSignature = formStateSignature();
    _attachFormListeners();
  }

  final RemoteTool? initialTool;

  late final TextEditingController nameC;
  late final TextEditingController pathC;
  late final TextEditingController iconC;
  late final TextEditingController testIpC;

  String? _suggestedValuesJson;

  int _initialSortOrder = 0;

  final FocusNode nameFocus = FocusNode();

  int? focusedArgRowIndex;
  bool focusedArgIsDescription = false;

  String launchMode = 'direct_exec';
  ToolRole role = ToolRole.generic;
  bool isActive = true;
  bool saving = false;

  final List<RemoteToolArgRow> argRows = [];
  int nextArgId = 0;

  late String initialFormSignature;

  bool get isEdit => initialTool != null;

  bool get isDirty => formStateSignature() != initialFormSignature;

  bool get createHasRequiredFields =>
      nameC.text.trim().isNotEmpty && pathC.text.trim().isNotEmpty;

  bool get canSubmitSave =>
      !saving && isDirty && (isEdit ? true : createHasRequiredFields);

  bool get canRunTest => testIpC.text.trim().isNotEmpty;

  String get testCommandPreview {
    if (!canRunTest) return '';
    final id = initialTool?.id ?? 0;
    return RemoteLauncherService.formatTestCommandPreview(toRemoteTool(id: id));
  }

  String get testButtonTooltip {
    if (!canRunTest) {
      return 'Ορίστε δοκιμαστική IP ή hostname στο πεδίο παραπάνω για να εκτελέσετε δοκιμή.';
    }
    return testCommandPreview;
  }

  String createPrimaryButtonTooltip() {
    if (saving) return 'Γίνεται αποθήκευση…';
    final hasName = nameC.text.trim().isNotEmpty;
    final hasPath = pathC.text.trim().isNotEmpty;
    if (!hasName && !hasPath) {
      return 'Πρέπει να συμπληρώσετε Όνομα Εργαλείου και Διαδρομή Εκτελέσιμου.';
    }
    if (!hasName) {
      return 'Πρέπει να συμπληρώσετε Όνομα Εργαλείου.';
    }
    if (!hasPath) {
      return 'Πρέπει να συμπληρώσετε Διαδρομή Εκτελέσιμου.';
    }
    if (!isDirty) {
      return 'Αλλάξτε κάποιο πεδίο για να ενεργοποιηθεί η Δημιουργία.';
    }
    return 'Αποθήκευση του νέου εργαλείου.';
  }

  String formStateSignature() {
    final sb = StringBuffer()
      ..write(nameC.text)
      ..write('\u001e')
      ..write(pathC.text)
      ..write('\u001e')
      ..write(iconC.text)
      ..write('\u001e')
      ..write(testIpC.text)
      ..write('\u001e')
      ..write(launchMode)
      ..write('\u001e')
      ..write(role.index)
      ..write('\u001e')
      ..write(isActive);
    for (final r in argRows) {
      sb
        ..write('\u001e')
        ..write(r.valueC.text)
        ..write('\u001f')
        ..write(r.descC.text)
        ..write('\u001f')
        ..write(r.active);
    }
    return sb.toString();
  }

  void markFormChanged() => notifyListeners();

  /// Ειδοποίηση ακροατών (κλήση από widget μετά από αλλαγή κατάστασης).
  void refresh() => notifyListeners();

  void onArgFieldFocused(int stableId, bool isDescription) {
    final idx = argRows.indexWhere((r) => r.stableId == stableId);
    if (idx < 0) return;
    focusedArgRowIndex = idx;
    focusedArgIsDescription = isDescription;
  }

  RemoteToolArgRow createArgRow({
    required int stableId,
    String value = '',
    String desc = '',
    bool active = true,
  }) {
    final valueC = TextEditingController(text: value);
    final descC = SpellCheckController()..text = desc;
    final valueFocus = FocusNode();
    final descFocus = FocusNode();
    valueFocus.addListener(() {
      if (valueFocus.hasFocus) onArgFieldFocused(stableId, false);
    });
    descFocus.addListener(() {
      if (descFocus.hasFocus) onArgFieldFocused(stableId, true);
    });
    valueC.addListener(markFormChanged);
    descC.addListener(markFormChanged);
    return RemoteToolArgRow(
      stableId: stableId,
      valueC: valueC,
      descC: descC,
      active: active,
      valueFocus: valueFocus,
      descFocus: descFocus,
    );
  }

  List<RemoteToolArgument> collectArguments() {
    return argRows
        .map(
          (r) => RemoteToolArgument(
            value: r.valueC.text.trim(),
            description: r.descC.text.trim(),
            isActive: r.active,
          ),
        )
        .where((a) => a.value.isNotEmpty)
        .toList();
  }

  RemoteTool toRemoteTool({required int id, int? sortOrder}) {
    final sort = sortOrder ?? _initialSortOrder;
    return RemoteTool(
      id: id,
      name: nameC.text.trim(),
      role: role,
      executablePath: pathC.text.trim(),
      launchMode: launchMode,
      sortOrder: sort,
      isActive: isActive,
      suggestedValuesJson: _suggestedValuesJson,
      iconAssetKey: iconC.text.trim().isEmpty ? null : iconC.text.trim(),
      arguments: collectArguments(),
      testTargetIp: testIpC.text.trim().isEmpty ? null : testIpC.text.trim(),
      isExclusive: false,
    );
  }

  bool isDuplicateName(
    List<RemoteTool> nonDeleted,
    String name,
    int? excludeId,
  ) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return false;
    for (final t in nonDeleted) {
      if (excludeId != null && t.id == excludeId) continue;
      if (t.name.trim().toLowerCase() == n) return true;
    }
    return false;
  }

  String? validateName(List<RemoteTool> nonDeleted) {
    final v = nameC.text.trim();
    if (v.isEmpty) return 'Υποχρεωτικό όνομα εργαλείου.';
    if (isDuplicateName(nonDeleted, v, isEdit ? initialTool!.id : null)) {
      return 'Υπάρχει ήδη εργαλείο με αυτό το όνομα.';
    }
    return null;
  }

  void addArg() {
    argRows.add(createArgRow(stableId: nextArgId++));
    notifyListeners();
  }

  void removeArg(int index) {
    argRows[index].valueC.removeListener(markFormChanged);
    argRows[index].descC.removeListener(markFormChanged);
    argRows[index].dispose();
    argRows.removeAt(index);
    if (focusedArgRowIndex == index) {
      focusedArgRowIndex = null;
    } else if (focusedArgRowIndex != null && focusedArgRowIndex! > index) {
      focusedArgRowIndex = focusedArgRowIndex! - 1;
    }
    notifyListeners();
  }

  void reorderArgs(int oldIndex, int newIndex) {
    final item = argRows.removeAt(oldIndex);
    argRows.insert(newIndex, item);
    notifyListeners();
  }

  void setArgActive(int index, bool active) {
    argRows[index].active = active;
    notifyListeners();
  }

  void applyRolePreset(ToolRole presetRole) {
    if (saving) return;
    final String line;
    switch (presetRole) {
      case ToolRole.vnc:
        line = '-host=PC{EQUIPMENT_CODE}';
      case ToolRole.rdp:
        line = '/v:{TARGET}';
      case ToolRole.anydesk:
        line = '-id {TARGET}';
      case ToolRole.generic:
        return;
    }
    if (argRows.any((r) => r.valueC.text.trim() == line)) return;
    argRows.add(createArgRow(stableId: nextArgId++, value: line));
    notifyListeners();
  }

  void _insertTextAtSelection(TextEditingController controller, String text) {
    final value = controller.value;
    final fullText = value.text;
    final sel = value.selection;
    final start = sel.start >= 0 ? sel.start : fullText.length;
    final end = sel.end >= 0 ? sel.end : fullText.length;
    final insertAt = start < end ? start : end;
    final replaceEnd = start < end ? end : start;
    final newText = fullText.replaceRange(insertAt, replaceEnd, text);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertAt + text.length),
    );
  }

  /// Εισαγωγή placeholder· επιστρέφει [FocusNode] προς επαναφορά εστίασης (ή null).
  FocusNode? insertPlaceholder(String token) {
    if (argRows.isEmpty) {
      argRows.add(createArgRow(stableId: nextArgId++, value: token));
      notifyListeners();
      return null;
    }

    late final TextEditingController targetController;
    late final FocusNode focusToRestore;

    if (focusedArgRowIndex != null &&
        focusedArgRowIndex! >= 0 &&
        focusedArgRowIndex! < argRows.length) {
      final row = argRows[focusedArgRowIndex!];
      if (focusedArgIsDescription) {
        targetController = row.descC;
        focusToRestore = row.descFocus;
      } else {
        targetController = row.valueC;
        focusToRestore = row.valueFocus;
      }
    } else {
      final row = argRows.last;
      targetController = row.valueC;
      focusToRestore = row.valueFocus;
    }

    _insertTextAtSelection(targetController, token);
    notifyListeners();
    return focusToRestore;
  }

  void _attachFormListeners() {
    for (final c in [nameC, pathC, iconC, testIpC]) {
      c.addListener(markFormChanged);
    }
    for (final r in argRows) {
      r.valueC.addListener(markFormChanged);
      r.descC.addListener(markFormChanged);
    }
  }

  void _detachFormListeners() {
    for (final c in [nameC, pathC, iconC, testIpC]) {
      c.removeListener(markFormChanged);
    }
    for (final r in argRows) {
      r.valueC.removeListener(markFormChanged);
      r.descC.removeListener(markFormChanged);
    }
  }

  @override
  void dispose() {
    _detachFormListeners();
    nameFocus.dispose();
    nameC.dispose();
    pathC.dispose();
    iconC.dispose();
    testIpC.dispose();
    for (final r in argRows) {
      r.dispose();
    }
    super.dispose();
  }
}
