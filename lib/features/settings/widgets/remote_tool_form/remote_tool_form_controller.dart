import 'package:flutter/material.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/services/overridable_settings.dart';
import '../../../../core/services/remote_tool_connect_wait.dart';
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
  RemoteToolFormController({RemoteTool? initialTool})
    : initialTool = initialTool {
    final t = initialTool;
    nameC = TextEditingController(text: t?.name ?? '');
    pathC = TextEditingController(text: t?.executablePath ?? '');
    iconC = TextEditingController(text: t?.iconAssetKey ?? '');
    _initialSortOrder = t?.sortOrder ?? 0;
    role = t?.role ?? ToolRole.generic;
    _suggestedValuesJson = t?.suggestedValuesJson;
    testIpC = TextEditingController(text: t?.testTargetIp ?? '');
    connectWaitC = TextEditingController(
      text: '${t?.connectWaitSeconds ?? RemoteTool.defaultConnectWaitSeconds}',
    );
    localPathC = TextEditingController();
    localWaitC = TextEditingController();
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

  /// Η **κοινή** αφετηρία αναμονής μετά την εκκίνηση, σε δευτερόλεπτα. Ο κάθε
  /// υπολογιστής την παρακάμπτει χωριστά.
  late final TextEditingController connectWaitC;

  /// Οι δύο τοπικές παρακάμψεις — διαδρομή και χρόνος αναμονής **σε αυτόν τον
  /// υπολογιστή**.
  ///
  /// Ζουν αλλού από τον κοινό ορισμό (στις προτιμήσεις του σταθμού, όχι στη
  /// βάση), αλλά **αποθηκεύονται με το ίδιο κουμπί**. Ως τώρα γράφονταν μόνες
  /// τους μόλις έφευγε η εστίαση: το «Αποθήκευση» έμενε γκρι, και ο χρήστης
  /// που έγραφε τιμή δεν μάθαινε ποτέ αν πιάστηκε. Μία φόρμα, μία κίνηση.
  late final TextEditingController localPathC;
  late final TextEditingController localWaitC;

  /// Η τριπλή κατάσταση της τοπικής διαδρομής: «καμία παράκαμψη» ≠ «δική μου
  /// και επίτηδες κενή» («κανένα πρόγραμμα εδώ»). Χωρίς αυτό, όποιος άδειαζε
  /// το πεδίο δεν θα μπορούσε να ξεχωρίσει τα δύο.
  bool localPathHasOverride = false;

  /// Οι τοπικές τιμές φορτώνονται ασύγχρονα· ώσπου να έρθουν, τα πεδία δεν
  /// εμφανίζονται και η αφετηρία της φόρμας δεν έχει οριστεί ακόμη.
  bool localOverridesLoaded = false;

  String _initialLocalPath = '';
  bool _initialLocalPathHasOverride = false;
  String _initialLocalWait = '';

  String? _suggestedValuesJson;

  int _initialSortOrder = 0;

  final FocusNode nameFocus = FocusNode();

  int? focusedArgRowIndex;
  bool focusedArgIsDescription = false;

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
      ..write(connectWaitC.text)
      ..write('\u001e')
      ..write(localPathHasOverride)
      ..write('\u001e')
      ..write(localPathC.text)
      ..write('\u001e')
      ..write(localWaitC.text)
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
      sortOrder: sort,
      isActive: isActive,
      suggestedValuesJson: _suggestedValuesJson,
      iconAssetKey: iconC.text.trim().isEmpty ? null : iconC.text.trim(),
      arguments: collectArguments(),
      testTargetIp: testIpC.text.trim().isEmpty ? null : testIpC.text.trim(),
      isExclusive: false,
      connectWaitSeconds: RemoteTool.normalizeConnectWaitSeconds(
        connectWaitC.text,
      ),
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
    for (final c in [
      nameC,
      pathC,
      iconC,
      testIpC,
      connectWaitC,
      localPathC,
      localWaitC,
    ]) {
      c.addListener(markFormChanged);
    }
    for (final r in argRows) {
      r.valueC.addListener(markFormChanged);
      r.descC.addListener(markFormChanged);
    }
  }

  void _detachFormListeners() {
    for (final c in [
      nameC,
      pathC,
      iconC,
      testIpC,
      connectWaitC,
      localPathC,
      localWaitC,
    ]) {
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
    connectWaitC.dispose();
    localPathC.dispose();
    localWaitC.dispose();
    for (final r in argRows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Φέρνει τις τοπικές παρακάμψεις αυτού του υπολογιστή.
  ///
  /// Έρχονται ασύγχρονα, οπότε **ξαναορίζουν την αφετηρία** της φόρμας: αν δεν
  /// το έκαναν, η άφιξή τους θα φαινόταν ως αλλαγή του χρήστη και το κουμπί
  /// «Αποθήκευση» θα άναβε χωρίς να έχει αγγίξει τίποτα.
  Future<void> loadLocalOverrides() async {
    final id = initialTool?.id;
    if (id != null) {
      final path = await OverridableSettings.overrideOf(
        OverridableSettingKeys.remoteToolExecutablePath.forId(id),
      );
      final wait = await RemoteToolConnectWait.localOverrideSeconds(id);
      localPathHasOverride = path != null;
      localPathC.text = path ?? '';
      localWaitC.text = wait == null ? '' : '$wait';
    }
    _initialLocalPath = localPathC.text;
    _initialLocalPathHasOverride = localPathHasOverride;
    _initialLocalWait = localWaitC.text;
    localOverridesLoaded = true;
    initialFormSignature = formStateSignature();
    notifyListeners();
  }

  /// Πληκτρολόγηση στο πεδίο διαδρομής σημαίνει «θέλω δική μου».
  void markLocalPathOverridden() {
    if (localPathHasOverride) return;
    localPathHasOverride = true;
    markFormChanged();
  }

  /// «Χρήση της κοινής διαδρομής»: αίρει τη δήλωση, δεν γράφει κενό.
  void useSharedPath() {
    localPathHasOverride = false;
    localPathC.text = '';
    markFormChanged();
  }

  /// «Χρήση της κοινής τιμής» για τον χρόνο: κενό πεδίο σημαίνει ακριβώς αυτό.
  void useSharedConnectWait() {
    localWaitC.text = '';
    markFormChanged();
  }

  bool get hasLocalOverrideChanges =>
      localPathC.text != _initialLocalPath ||
      localPathHasOverride != _initialLocalPathHasOverride ||
      localWaitC.text.trim() != _initialLocalWait.trim();

  /// Γράφει τις τοπικές παρακάμψεις. Καλείται μαζί με την αποθήκευση του
  /// κοινού ορισμού — ποτέ χωριστά.
  Future<void> commitLocalOverrides(int toolId) async {
    final pathKey = OverridableSettingKeys.remoteToolExecutablePath.forId(
      toolId,
    );
    if (localPathHasOverride) {
      await OverridableSettings.setOverride(pathKey, localPathC.text.trim());
    } else {
      await OverridableSettings.clearOverride(pathKey);
    }

    final waitText = localWaitC.text.trim();
    if (waitText.isEmpty) {
      await RemoteToolConnectWait.clearLocalOverride(toolId);
    } else {
      await RemoteToolConnectWait.setLocalOverride(
        toolId,
        RemoteTool.normalizeConnectWaitSeconds(waitText),
      );
    }

    _initialLocalPath = localPathC.text;
    _initialLocalPathHasOverride = localPathHasOverride;
    _initialLocalWait = localWaitC.text;
  }

  /// Οι γραμμές της σύνοψης αποθήκευσης για ό,τι άλλαξε **μόνο εδώ**.
  ///
  /// Χωριστές από τις αλλαγές του κοινού ορισμού, γιατί απαντούν σε άλλο
  /// ερώτημα: τι είδαν οι συνάδελφοι και τι μόνο αυτό το μηχάνημα.
  List<String> localOverrideChangeLines() {
    final lines = <String>[];
    if (localPathHasOverride != _initialLocalPathHasOverride ||
        localPathC.text != _initialLocalPath) {
      lines.add(
        localPathHasOverride
            ? (localPathC.text.trim().isEmpty
                  ? 'Διαδρομή σε αυτόν τον υπολογιστή: κανένα πρόγραμμα'
                  : 'Διαδρομή σε αυτόν τον υπολογιστή: ${localPathC.text.trim()}')
            : 'Διαδρομή σε αυτόν τον υπολογιστή: χρήση της κοινής',
      );
    }
    final waitText = localWaitC.text.trim();
    if (waitText != _initialLocalWait.trim()) {
      final seconds = waitText.isEmpty
          ? null
          : RemoteTool.normalizeConnectWaitSeconds(waitText);
      lines.add(switch (seconds) {
        null => 'Αναμονή σε αυτόν τον υπολογιστή: χρήση της κοινής',
        0 => 'Αναμονή σε αυτόν τον υπολογιστή: χωρίς κλείδωμα',
        final int v => 'Αναμονή σε αυτόν τον υπολογιστή: $v δευτ.',
      });
    }
    return lines;
  }
}
