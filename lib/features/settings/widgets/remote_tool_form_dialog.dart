import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_role.dart';
import '../../../core/services/remote_launcher_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/file_picker_initial_directory.dart';
import '../../../core/database/remote_tools_repository.dart';
import '../../calls/provider/remote_paths_provider.dart';

enum _SoftDeletedNameChoice { restore, keepSameName }

/// Ταξινόμηση όπως στο [RemoteToolsRepository] (sort_order, name, id).
List<RemoteTool> sortedRemoteTools(List<RemoteTool> tools) {
  final s = [...tools]..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        if (c != 0) return c;
        final n = a.name.compareTo(b.name);
        if (n != 0) return n;
        return a.id.compareTo(b.id);
      });
  return s;
}

/// Επεξεργασία ή δημιουργία εργαλείου απομακρυσμένης σύνδεσης (ορίσματα JSON στο `remote_tools`).
Future<bool> showRemoteToolFormDialog(
  BuildContext context,
  WidgetRef ref, {
  RemoteTool? tool,
}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => RemoteToolFormDialog(initialTool: tool),
  );
  return r ?? false;
}

class RemoteToolFormDialog extends ConsumerStatefulWidget {
  const RemoteToolFormDialog({super.key, this.initialTool});

  /// null = νέο εργαλείο.
  final RemoteTool? initialTool;

  @override
  ConsumerState<RemoteToolFormDialog> createState() =>
      _RemoteToolFormDialogState();
}

class _ArgRow {
  _ArgRow({
    required this.stableId,
    required this.valueC,
    required this.descC,
    required this.active,
  });

  final int stableId;
  final TextEditingController valueC;
  final TextEditingController descC;
  bool active;

  void dispose() {
    valueC.dispose();
    descC.dispose();
  }
}

class _RemoteToolFormDialogState extends ConsumerState<RemoteToolFormDialog> {
  late final TextEditingController _nameC;
  late final TextEditingController _pathC;
  late final TextEditingController _iconC;
  late final TextEditingController _suggC;
  late final TextEditingController _testIpC;

  final FocusNode _nameFocus = FocusNode();

  String _launchMode = 'direct_exec';
  ToolRole _role = ToolRole.generic;
  bool _isActive = true;
  bool _isExclusive = false;
  bool _saving = false;

  /// Καθρέφτης της καθολικής ρύθμισης [SettingsService] (όχι μέρος του εργαλείου).
  bool _remotePrioritySwapMode = false;

  /// Για νέο εργαλείο: προεπιλογή τελευταίας θέσης μετά το πρώτο frame (όταν είναι γνωστό το πλήθος).
  bool _newPriorityBootstrapped = false;
  bool _newPriorityBootstrapScheduled = false;

  /// Θέση 1..N στην ουρά ταξινόμησης (μη διαγραμμένα).
  late int _priorityOneBased;

  final List<_ArgRow> _argRows = [];
  int _nextArgId = 0;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// Στιγμιότυπο αρχικής κατάστασης για ενεργοποίηση «Αποθήκευση» μόνο όταν υπάρχει αλλαγή.
  late String _initialFormSignature;

  bool get _isEdit => widget.initialTool != null;

  /// Αλλαγή οποιουδήποτε πεδίου ή ορίσματος σε σχέση με το `_initialFormSignature`.
  bool get _isDirty => _formStateSignature() != _initialFormSignature;

  /// Νέο εργαλείο: υποχρεωτικά όνομα και διαδρομή εκτελέσιμου πριν επιτραπεί αποθήκευση.
  bool get _createHasRequiredFields =>
      _nameC.text.trim().isNotEmpty && _pathC.text.trim().isNotEmpty;

  bool get _canSubmitSave =>
      !_saving &&
      _isDirty &&
      (_isEdit ? true : _createHasRequiredFields);

  /// Tooltip μόνο για το κουμπί «Δημιουργία» (νέο εργαλείο).
  String _createPrimaryButtonTooltip() {
    if (_saving) return 'Γίνεται αποθήκευση…';
    final hasName = _nameC.text.trim().isNotEmpty;
    final hasPath = _pathC.text.trim().isNotEmpty;
    if (!hasName && !hasPath) {
      return 'Πρέπει να συμπληρώσετε Όνομα Εργαλείου και Διαδρομή Εκτελέσιμου.';
    }
    if (!hasName) {
      return 'Πρέπει να συμπληρώσετε Όνομα Εργαλείου.';
    }
    if (!hasPath) {
      return 'Πρέπει να συμπληρώσετε Διαδρομή Εκτελέσιμου.';
    }
    if (!_isDirty) {
      return 'Αλλάξτε κάποιο πεδίο για να ενεργοποιηθεί η Δημιουργία.';
    }
    return 'Αποθήκευση του νέου εργαλείου.';
  }

  String _formStateSignature() {
    final sb = StringBuffer()
      ..write(_nameC.text)
      ..write('\u001e')
      ..write(_pathC.text)
      ..write('\u001e')
      ..write(_iconC.text)
      ..write('\u001e')
      ..write(_suggC.text)
      ..write('\u001e')
      ..write(_testIpC.text)
      ..write('\u001e')
      ..write(_launchMode)
      ..write('\u001e')
      ..write(_role.index)
      ..write('\u001e')
      ..write(_isActive)
      ..write('\u001e')
      ..write(_isExclusive)
      ..write('\u001e')
      ..write(_priorityOneBased);
    for (final r in _argRows) {
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

  void _markFormChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    final t = widget.initialTool;
    _nameC = TextEditingController(text: t?.name ?? '');
    _pathC = TextEditingController(text: t?.executablePath ?? '');
    _iconC = TextEditingController(text: t?.iconAssetKey ?? '');
    _priorityOneBased = t?.sortOrder ?? 1;
    if (_priorityOneBased < 1) _priorityOneBased = 1;
    _role = t?.role ?? ToolRole.generic;
    _suggC = TextEditingController(text: t?.suggestedValuesJson ?? '');
    _testIpC = TextEditingController(text: t?.testTargetIp ?? '');
    _launchMode = t?.launchMode ?? 'direct_exec';
    _isActive = t?.isActive ?? true;
    _isExclusive = t?.isExclusive ?? false;
    if (t != null && t.arguments.isNotEmpty) {
      for (final a in t.arguments) {
        _argRows.add(
          _ArgRow(
            stableId: _nextArgId++,
            valueC: TextEditingController(text: a.value),
            descC: TextEditingController(text: a.description),
            active: a.isActive,
          ),
        );
      }
    }
    _initialFormSignature = _formStateSignature();
    _attachFormListeners();
    _loadRemotePriorityMode();
  }

  Future<void> _loadRemotePriorityMode() async {
    final v = await SettingsService().getRemoteToolPrioritySwapMode();
    if (!mounted) return;
    setState(() => _remotePrioritySwapMode = v);
  }

  void _attachFormListeners() {
    for (final c in [
      _nameC,
      _pathC,
      _iconC,
      _suggC,
      _testIpC,
    ]) {
      c.addListener(_markFormChanged);
    }
    for (final r in _argRows) {
      r.valueC.addListener(_markFormChanged);
      r.descC.addListener(_markFormChanged);
    }
  }

  void _detachFormListeners() {
    for (final c in [
      _nameC,
      _pathC,
      _iconC,
      _suggC,
      _testIpC,
    ]) {
      c.removeListener(_markFormChanged);
    }
    for (final r in _argRows) {
      r.valueC.removeListener(_markFormChanged);
      r.descC.removeListener(_markFormChanged);
    }
  }

  bool get _canRunTest => _testIpC.text.trim().isNotEmpty;

  String get _testButtonTooltip {
    if (!_canRunTest) {
      return 'Ορίστε δοκιμαστική IP ή hostname στο πεδίο παραπάνω για να εκτελέσετε δοκιμή.';
    }
    final id = widget.initialTool?.id ?? 0;
    return RemoteLauncherService.formatTestCommandPreview(_toolFromForm(id: id));
  }

  @override
  void dispose() {
    _detachFormListeners();
    _nameFocus.dispose();
    _nameC.dispose();
    _pathC.dispose();
    _iconC.dispose();
    _suggC.dispose();
    _testIpC.dispose();
    for (final r in _argRows) {
      r.dispose();
    }
    super.dispose();
  }

  List<RemoteToolArgument> _collectArguments() {
    return _argRows
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

  RemoteTool _toolFromForm({required int id, int? sortOrder}) {
    final sort = sortOrder ?? _priorityOneBased;
    return RemoteTool(
      id: id,
      name: _nameC.text.trim(),
      role: _role,
      executablePath: _pathC.text.trim(),
      launchMode: _launchMode,
      sortOrder: sort,
      isActive: _isActive,
      suggestedValuesJson:
          _suggC.text.trim().isEmpty ? null : _suggC.text.trim(),
      iconAssetKey: _iconC.text.trim().isEmpty ? null : _iconC.text.trim(),
      arguments: _collectArguments(),
      testTargetIp: _testIpC.text.trim().isEmpty ? null : _testIpC.text.trim(),
      isExclusive: _isExclusive,
    );
  }

  bool _isDuplicateName(List<RemoteTool> nonDeleted, String name, int? excludeId) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return false;
    for (final t in nonDeleted) {
      if (excludeId != null && t.id == excludeId) continue;
      if (t.name.trim().toLowerCase() == n) return true;
    }
    return false;
  }

  String? _validateName(List<RemoteTool> nonDeleted) {
    final v = _nameC.text.trim();
    if (v.isEmpty) return 'Υποχρεωτικό όνομα εργαλείου.';
    if (_isDuplicateName(nonDeleted, v, _isEdit ? widget.initialTool!.id : null)) {
      return 'Υπάρχει ήδη εργαλείο με αυτό το όνομα.';
    }
    return null;
  }

  Future<void> _pickExecutable() async {
    final initial = initialDirectoryForFilePicker(_pathC.text);
    final r = await FilePicker.pickFiles(
      type: FileType.any,
      dialogTitle: 'Εκτελέσιμο',
      initialDirectory: initial,
    );
    if (r != null && r.files.isNotEmpty) {
      final p = r.files.single.path;
      if (p != null) {
        _pathC.text = p;
        setState(() {});
      }
    }
  }

  Future<void> _pickIcon() async {
    final initial = initialDirectoryForFilePicker(_iconC.text);
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'svg', 'ico'],
      dialogTitle: 'Εικονίδιο εργαλείου',
      initialDirectory: initial,
    );
    if (r != null && r.files.isNotEmpty) {
      final p = r.files.single.path;
      if (p != null) {
        _iconC.text = p;
        setState(() {});
      }
    }
  }

  Future<_SoftDeletedNameChoice?> _showSoftDeletedNameConflictDialog(
    RemoteTool softDeleted,
  ) {
    return showDialog<_SoftDeletedNameChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Διεγραμμένο εργαλείο με το ίδιο όνομα'),
        content: Text(
          'Υπάρχει διεγραμμένη εγγραφή «${softDeleted.name}». '
          'Μπορείτε να την επαναφέρετε με τα στοιχεία της φόρμας, ή να συνεχίσετε '
          'με το ίδιο εμφανιζόμενο όνομα (η παλιά εγγραφή μετονομάζεται εσωτερικά).',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_SoftDeletedNameChoice.keepSameName),
            child: const Text('Ίδιο όνομα (παλιά → αρχείο)'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_SoftDeletedNameChoice.restore),
            child: const Text('Επαναφορά διεγραμμένου'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyRolePaths(RemoteTool t) async {
    if (t.role == ToolRole.vnc) {
      await SettingsService().setVncPath(t.executablePath);
    } else if (t.role == ToolRole.anydesk) {
      await SettingsService().setAnydeskPath(t.executablePath);
    }
  }

  /// Επαναφορά soft-deleted γραμμής με τα περιεχόμενα της φόρμας· σε επεξεργασία
  /// άλλου id, η τρέχουσα εγγραφή διαγράφεται (soft).
  Future<void> _saveRestoringSoftDeleted(
    RemoteToolsRepository repo,
    List<RemoteTool> allNonDeleted,
    RemoteTool softDeleted,
  ) async {
    final n = allNonDeleted.length;
    final sorted = sortedRemoteTools(allNonDeleted);
    final swap = _remotePrioritySwapMode && n > 0;
    final maxSort = n + 1;
    final maxSwap = n;
    final sortClamped = swap
        ? _priorityOneBased.clamp(1, maxSwap)
        : _priorityOneBased.clamp(1, maxSort);
    final insertOrder = swap ? (n + 1) : sortClamped;
    final restored = _toolFromForm(id: softDeleted.id, sortOrder: insertOrder);
    await repo.restoreToolClearDeleted(restored);
    if (_isEdit && widget.initialTool!.id != softDeleted.id) {
      await repo.deleteTool(widget.initialTool!.id);
    }
    if (swap && n > 0) {
      final targetPos = sortClamped.clamp(1, n);
      final other = sorted[targetPos - 1];
      await repo.swapSortOrderBetweenTools(
        toolIdA: softDeleted.id,
        toolIdB: other.id,
      );
    } else {
      await repo.reorderToolToPosition(
        toolId: softDeleted.id,
        positionOneBased: sortClamped,
      );
    }
    await _applyRolePaths(restored);
    _invalidateRemote();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final repo = ref.read(remoteToolsRepositoryProvider);
    final all = await repo.getAllNonDeletedTools();
    final err = _validateName(all);
    if (err != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final nameTrim = _nameC.text.trim();
    final softDeleted = await repo.findFirstSoftDeletedByNameInsensitive(
      nameTrim,
      excludeToolId: _isEdit ? widget.initialTool!.id : null,
    );
    if (softDeleted != null) {
      final choice = await _showSoftDeletedNameConflictDialog(softDeleted);
      if (!mounted) return;
      if (choice == null) return;
      if (choice == _SoftDeletedNameChoice.restore) {
        setState(() => _saving = true);
        try {
          await _saveRestoringSoftDeleted(repo, all, softDeleted);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Σφάλμα: $e'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        } finally {
          if (mounted) setState(() => _saving = false);
        }
        return;
      }
      await repo.disambiguateSoftDeletedToolName(softDeleted.id);
    }

    setState(() => _saving = true);
    try {
      final fresh = await repo.getAllNonDeletedTools();
      final n = fresh.length;
      final sorted = sortedRemoteTools(fresh);
      final swap = _remotePrioritySwapMode && n > 0;
      final maxSort = _isEdit ? n : n + 1;
      final maxSwap = n;
      final sortClamped = swap
          ? _priorityOneBased.clamp(1, maxSwap)
          : _priorityOneBased.clamp(1, maxSort);

      if (_isEdit) {
        final id = widget.initialTool!.id;
        final self = sorted.firstWhere((t) => t.id == id);
        final updated = _toolFromForm(
          id: id,
          sortOrder: swap ? self.sortOrder : sortClamped,
        );
        await repo.updateTool(updated);
        if (swap) {
          final curPos = sorted.indexWhere((t) => t.id == id) + 1;
          final targetPos = sortClamped;
          if (targetPos != curPos) {
            final other = sorted[targetPos - 1];
            await repo.swapSortOrderBetweenTools(
              toolIdA: id,
              toolIdB: other.id,
            );
          }
        } else {
          await repo.reorderToolToPosition(
            toolId: id,
            positionOneBased: sortClamped,
          );
        }
        await _applyRolePaths(updated);
      } else {
        final sortedBefore = sorted;
        final insertOrder = swap ? (n + 1) : sortClamped;
        final toInsert = _toolFromForm(id: 0, sortOrder: insertOrder);
        final newId = await repo.insertTool(toInsert);
        if (swap && n > 0) {
          final targetPos = sortClamped.clamp(1, n);
          final other = sortedBefore[targetPos - 1];
          await repo.swapSortOrderBetweenTools(
            toolIdA: newId,
            toolIdB: other.id,
          );
        } else {
          await repo.reorderToolToPosition(
            toolId: newId,
            positionOneBased: sortClamped,
          );
        }
        await _applyRolePaths(toInsert);
      }
      _invalidateRemote();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Σφάλμα: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _invalidateRemote() {
    ref.invalidate(remoteToolsAllCatalogProvider);
    ref.invalidate(remoteToolsCatalogProvider);
    ref.invalidate(remoteToolFormPairsProvider);
    ref.invalidate(remotePathsProvider);
    ref.invalidate(validRemoteToolPathsByIdProvider);
    ref.invalidate(validRemotePathsProvider);
    ref.invalidate(remoteLauncherStatusesByIdProvider);
    ref.invalidate(remoteLauncherStatusProvider);
  }

  Future<void> _runTest() async {
    final id = widget.initialTool?.id ?? 0;
    final tool = _toolFromForm(id: id);
    try {
      await ref.read(remoteLauncherServiceProvider).testRemoteTool(tool);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Η δοκιμή ξεκίνησε (ενεργά ορίσματα + δοκιμαστικός στόχος).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _addArg() {
    setState(() {
      final row = _ArgRow(
        stableId: _nextArgId++,
        valueC: TextEditingController(),
        descC: TextEditingController(),
        active: true,
      );
      row.valueC.addListener(_markFormChanged);
      row.descC.addListener(_markFormChanged);
      _argRows.add(row);
    });
  }

  void _removeArg(int index) {
    setState(() {
      _argRows[index].valueC.removeListener(_markFormChanged);
      _argRows[index].descC.removeListener(_markFormChanged);
      _argRows[index].dispose();
      _argRows.removeAt(index);
    });
  }

  void _onReorderArgs(int oldIndex, int newIndex) {
    setState(() {
      var ni = newIndex;
      if (ni > oldIndex) ni -= 1;
      final item = _argRows.removeAt(oldIndex);
      _argRows.insert(ni, item);
    });
  }

  Future<void> _onRoleChanged(ToolRole v) async {
    final prev = _role;
    setState(() => _role = v);
    if (prev == v || !mounted) return;
    final offer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Προτεινόμενα ορίσματα'),
        content: Text(
          'Να προστεθούν τυπικά ορίσματα για τον ρόλο «${v.dbValue}»;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Όχι'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ναι'),
          ),
        ],
      ),
    );
    if (offer == true && mounted) {
      _applyRolePreset(v);
    }
  }

  void _applyRolePreset(ToolRole presetRole) {
    if (_saving) return;
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
    if (_argRows.any((r) => r.valueC.text.trim() == line)) return;
    setState(() {
      final row = _ArgRow(
        stableId: _nextArgId++,
        valueC: TextEditingController(text: line),
        descC: TextEditingController(),
        active: true,
      );
      row.valueC.addListener(_markFormChanged);
      row.descC.addListener(_markFormChanged);
      _argRows.add(row);
    });
  }

  void _insertPlaceholder(String token) {
    setState(() {
      if (_argRows.isEmpty) {
        final row = _ArgRow(
          stableId: _nextArgId++,
          valueC: TextEditingController(text: token),
          descC: TextEditingController(),
          active: true,
        );
        row.valueC.addListener(_markFormChanged);
        row.descC.addListener(_markFormChanged);
        _argRows.add(row);
      } else {
        final c = _argRows.last.valueC;
        c.text = c.text.isEmpty ? token : '${c.text}$token';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);
    final asyncTools = ref.watch(remoteToolsAllCatalogProvider);

    return asyncTools.when(
      loading: () => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 620, maxHeight: mq.height * 0.85),
          child: const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
      error: (e, _) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Φόρτωση καταλόγου: $e'),
        ),
      ),
      data: (allTools) {
        final nonDeleted = sortedRemoteTools(
          allTools.where((t) => t.deletedAt == null).toList(),
        );
        final n = nonDeleted.length;
        final maxPrioritySort = _isEdit ? n : n + 1;
        final swap = _remotePrioritySwapMode && n > 0;
        final maxPriority = swap ? n : maxPrioritySort;
        if (!_isEdit &&
            !_newPriorityBootstrapped &&
            !_newPriorityBootstrapScheduled) {
          _newPriorityBootstrapScheduled = true;
          final lastSlot = n + 1;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _newPriorityBootstrapped) return;
            setState(() {
              _newPriorityBootstrapped = true;
              _priorityOneBased = lastSlot;
              _initialFormSignature = _formStateSignature();
            });
          });
        }
        final effectivePriority = _priorityOneBased.clamp(1, maxPriority);
        final nameSuggestions = nonDeleted
            .map((t) => t.name.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 620,
              maxHeight: mq.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text(
                    _isEdit
                        ? 'Επεξεργασία · ${widget.initialTool!.name}'
                        : 'Νέο εργαλείο',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle(theme, 'Βασικά στοιχεία'),
                          const Divider(),
                          _NameAutocompleteField(
                            controller: _nameC,
                            focusNode: _nameFocus,
                            suggestions: nameSuggestions,
                            excludeId: _isEdit ? widget.initialTool!.id : null,
                            nonDeleted: nonDeleted,
                            isCreate: !_isEdit,
                          ),
                          const SizedBox(height: 12),
                          _PriorityRow(
                            sortedTools: nonDeleted,
                            value: effectivePriority,
                            maxPrioritySort: maxPrioritySort,
                            swapMode: swap,
                            swapEnabled: n > 0,
                            newToolNamePreview: _nameC.text.trim().isEmpty
                                ? 'νέο'
                                : _nameC.text.trim(),
                            isEdit: _isEdit,
                            onSwapModeChanged: _saving
                                ? null
                                : (swapNext) {
                                    SettingsService()
                                        .setRemoteToolPrioritySwapMode(
                                      swapNext,
                                    )
                                        .then((_) {
                                      if (!mounted) return;
                                      setState(() {
                                        _remotePrioritySwapMode = swapNext;
                                        if (swapNext) {
                                          _priorityOneBased = _priorityOneBased
                                              .clamp(1, n);
                                        } else {
                                          _priorityOneBased = _priorityOneBased
                                              .clamp(1, maxPrioritySort);
                                        }
                                      });
                                    });
                                  },
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _priorityOneBased = v),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Ενεργό εργαλείο'),
                            subtitle: Text(
                              'Όταν είναι ανενεργό, δεν εμφανίζεται στις κλήσεις.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            value: _isActive,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _isActive = v),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Αποκλειστική χρήση (κρύβει τα υπόλοιπα)',
                            ),
                            subtitle: Text(
                              'Όταν είναι ενεργό στην κλήση, εμφανίζονται μόνο αποκλειστικά εργαλεία.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            value: _isExclusive,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _isExclusive = v),
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(theme, 'Εκτέλεση'),
                          const Divider(),
                          _ExecutablePathField(
                            controller: _pathC,
                            onPick: _pickExecutable,
                            enabled: !_saving,
                            isCreate: !_isEdit,
                          ),
                          const SizedBox(height: 12),
                          _LaunchModeSelector(
                            value: _launchMode,
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _launchMode = v),
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(theme, 'Εικονίδιο εργαλείου'),
                          const Divider(),
                          _IconFieldWithPreview(
                            controller: _iconC,
                            onPick: _pickIcon,
                            enabled: !_saving,
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(theme, 'Συμπεριφορά και Ρόλος'),
                          const Divider(),
                          _RoleDropdown(
                            value: _role,
                            onChanged: _saving
                                ? null
                                : (v) => _onRoleChanged(v),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PopupMenuButton<ToolRole>(
                              enabled: !_saving,
                              tooltip: 'Προεπιλογές ρόλου',
                              onSelected: (r) {
                                if (!_saving) _applyRolePreset(r);
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: ToolRole.vnc,
                                  child: Text('VNC: -host=PC{EQUIPMENT_CODE}'),
                                ),
                                const PopupMenuItem(
                                  value: ToolRole.rdp,
                                  child: Text('RDP: /v:{TARGET}'),
                                ),
                                const PopupMenuItem(
                                  value: ToolRole.anydesk,
                                  child: Text('AnyDesk: -id {TARGET}'),
                                ),
                              ],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_fix_high_outlined,
                                      size: 20,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Προεπιλογές ρόλου',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    const Icon(Icons.arrow_drop_down),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(theme, 'Προχωρημένα'),
                          const Divider(),
                          TextFormField(
                            controller: _suggC,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Προτεινόμενες τιμές (JSON)',
                              helperText:
                                  'Προαιρετική δομή JSON για προτάσεις πεδίων.',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _testIpC,
                            decoration: const InputDecoration(
                              labelText:
                                  'Δοκιμαστική IP / Hostname (για δοκιμή)',
                              helperText:
                                  'Απαιτείται για το κουμπί «Δοκιμή εργαλείου».',
                              hintText: 'π.χ. 192.168.1.100',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(theme, 'Ορίσματα γραμμής εντολών'),
                          const Divider(),
                          Text(
                            'Placeholders: {TARGET}, {EQUIPMENT_CODE}, {FILE}. '
                            'Κωδικοί/χρήστης ως απλό κείμενο στο value (π.χ. /p:…). '
                            'Κενό value παραλείπεται στην αποθήκευση.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final ph in [
                                '{TARGET}',
                                '{EQUIPMENT_CODE}',
                                '{FILE}',
                              ])
                                FilledButton.tonal(
                                  onPressed:
                                      _saving ? null : () => _insertPlaceholder(ph),
                                  child: Text(ph),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: _saving ? null : _addArg,
                            icon: const Icon(Icons.add),
                            label: const Text('Προσθήκη ορίσματος'),
                          ),
                          const SizedBox(height: 12),
                          if (_argRows.isEmpty)
                            Text(
                              'Κανένα ορίσμα.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          else
                            ReorderableListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              onReorder: (o, n) {
                                if (!_saving) _onReorderArgs(o, n);
                              },
                              children: [
                                for (var i = 0; i < _argRows.length; i++)
                                  KeyedSubtree(
                                    key: ValueKey(_argRows[i].stableId),
                                    child: _ArgRowTile(
                                      index: i,
                                      row: _argRows[i],
                                      onRemove: () => _removeArg(i),
                                      onToggleActive: (v) => setState(
                                        () => _argRows[i].active = v ?? false,
                                      ),
                                      saving: _saving,
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Tooltip(
                                message: _testButtonTooltip,
                                showDuration: const Duration(seconds: 40),
                                waitDuration:
                                    const Duration(milliseconds: 400),
                                child: OutlinedButton.icon(
                                  onPressed:
                                      _saving || !_canRunTest ? null : _runTest,
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Δοκιμή εργαλείου'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Ακύρωση'),
                      ),
                      const SizedBox(width: 8),
                      _isEdit
                          ? FilledButton(
                              onPressed: _canSubmitSave ? _save : null,
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Αποθήκευση'),
                            )
                          : Tooltip(
                              message: _createPrimaryButtonTooltip(),
                              waitDuration:
                                  const Duration(milliseconds: 400),
                              child: FilledButton(
                                onPressed: _canSubmitSave ? _save : null,
                                child: _saving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Δημιουργία'),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _sectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Πεδίο ονόματος με RawAutocomplete και επικύρωση διπλοτύπου.
class _NameAutocompleteField extends StatelessWidget {
  const _NameAutocompleteField({
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.nonDeleted,
    required this.excludeId,
    this.isCreate = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final List<RemoteTool> nonDeleted;
  final int? excludeId;
  /// Στη δημιουργία: ετικέτα με * (υποχρεωτικό πεδίο).
  final bool isCreate;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (s) => s,
      optionsBuilder: (TextEditingValue tev) {
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) {
          return suggestions.take(16);
        }
        return suggestions
            .where((n) => n.toLowerCase().contains(q))
            .take(24);
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opt = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(opt),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: isCreate ? 'Όνομα εργαλείου *' : 'Όνομα εργαλείου',
            border: const OutlineInputBorder(),
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) {
            final name = v?.trim() ?? '';
            if (name.isEmpty) return 'Υποχρεωτικό όνομα εργαλείου.';
            final n = name.toLowerCase();
            for (final t in nonDeleted) {
              if (excludeId != null && t.id == excludeId) continue;
              if (t.name.trim().toLowerCase() == n) {
                return 'Υπάρχει ήδη εργαλείο με αυτό το όνομα.';
              }
            }
            return null;
          },
        );
      },
    );
  }
}

class _ExecutablePathField extends StatelessWidget {
  const _ExecutablePathField({
    required this.controller,
    required this.onPick,
    required this.enabled,
    this.isCreate = false,
  });

  final TextEditingController controller;
  final VoidCallback onPick;
  final bool enabled;
  /// Στη δημιουργία: ετικέτα με * (υποχρεωτικό πεδίο).
  final bool isCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = controller.text.trim();
    String? missingMsg;
    if (path.isNotEmpty) {
      final f = File(path);
      if (!f.existsSync()) {
        missingMsg = 'Το αρχείο δεν βρέθηκε στη διαδρομή.';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                maxLines: 1,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: isCreate
                      ? 'Διαδρομή εκτελέσιμου *'
                      : 'Διαδρομή εκτελέσιμου',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Εντοπισμός αρχείου',
              onPressed: enabled ? onPick : null,
              icon: const Icon(Icons.folder_open),
            ),
          ],
        ),
        if (missingMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              missingMsg,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _LaunchModeSelector extends StatelessWidget {
  const _LaunchModeSelector({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Τρόπος εκκίνησης',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        IgnorePointer(
          ignoring: onChanged == null,
          child: Opacity(
            opacity: onChanged == null ? 0.5 : 1,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'direct_exec',
                  label: Text('Άμεση εκτέλεση'),
                ),
                ButtonSegment(
                  value: 'template_file',
                  label: Text('Αρχείο προτύπου'),
                ),
              ],
              selected: {value},
              onSelectionChanged: (s) {
                if (s.isNotEmpty && onChanged != null) onChanged!(s.first);
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '«Άμεση εκτέλεση» περνά τα ορίσματα στο εκτελέσιμο. «Αρχείο προτύπου» = ίδια ροή· '
          'χρησιμοποιήστε {FILE} σε ενεργό όρισμα για σταθερή διαδρομή υπάρχοντος .rdp (π.χ. το αρχείο στο δίσκο).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _IconFieldWithPreview extends StatelessWidget {
  const _IconFieldWithPreview({
    required this.controller,
    required this.onPick,
    required this.enabled,
  });

  final TextEditingController controller;
  final VoidCallback onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = controller.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                decoration: const InputDecoration(
                  labelText: 'Εικονίδιο εργαλείου (path ή asset)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Επιλογή εικονιδίου',
              onPressed: enabled ? onPick : null,
              icon: const Icon(Icons.image_outlined),
            ),
            const SizedBox(width: 8),
            _IconPreview(text: raw),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 12),
          child: Text(
            'Διαδρομή προς εικόνα (.png/.svg/.ico) ή asset key. Χρησιμοποιείται στα κουμπιά απομακρυσμένης σύνδεσης. '
            'Προτεραιότητα στο iconAssetKey, fallback στο προεπιλεγμένο εικονίδιο.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    if (text.isEmpty) {
      return const SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0xFFE0E0E0)),
          child: Icon(Icons.image, size: 22),
        ),
      );
    }
    if (text.startsWith('assets/')) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          text,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image_outlined),
        ),
      );
    }
    final f = File(text);
    if (f.existsSync()) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.file(
          f,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image_outlined),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        text,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.image_outlined),
      ),
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({
    required this.value,
    required this.onChanged,
  });

  final ToolRole value;
  final ValueChanged<ToolRole>? onChanged;

  static String _label(ToolRole r) {
    return switch (r) {
      ToolRole.generic => 'Κανένα – Χωρίς αυτόματο στόχο',
      ToolRole.anydesk => 'AnyDesk-like',
      ToolRole.rdp => 'RDP Hostname/IP',
      ToolRole.vnc => 'VNC Host',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ToolRole>(
          key: ValueKey(value),
          initialValue: value,
          decoration: const InputDecoration(
            labelText: 'Ρόλος',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final r in ToolRole.values)
              DropdownMenuItem(value: r, child: Text(_label(r))),
          ],
          onChanged: onChanged == null
              ? null
              : (ToolRole? v) {
                  if (v != null) onChanged!(v);
                },
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Εσωτερική ετικέτα συμβατότητας: καθορίζει πώς επιλύεται ο στόχος σύνδεσης μέσω '
                'CallRemoteTargets.resolvedLaunchTarget (όχι ελεύθερο κείμενο στη βάση).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    required this.sortedTools,
    required this.value,
    required this.maxPrioritySort,
    required this.swapMode,
    required this.swapEnabled,
    required this.newToolNamePreview,
    required this.isEdit,
    required this.onSwapModeChanged,
    required this.onChanged,
  });

  final List<RemoteTool> sortedTools;
  final int value;
  final int maxPrioritySort;
  final bool swapMode;
  final bool swapEnabled;
  final String newToolNamePreview;
  final bool isEdit;
  final ValueChanged<bool>? onSwapModeChanged;
  final ValueChanged<int>? onChanged;

  String _labelForSortSlot(int i1Based) {
    final n = sortedTools.length;
    if (i1Based >= 1 && i1Based <= n) {
      return sortedTools[i1Based - 1].name;
    }
    if (!isEdit && i1Based == n + 1) {
      return newToolNamePreview;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = sortedTools.length;
    final maxP = swapMode ? n : maxPrioritySort;
    final safeMax = maxP < 1 ? 1 : maxP;
    final v = value.clamp(1, safeMax);
    final items = <int>[for (var i = 1; i <= safeMax; i++) i];

    final helper = swapMode
        ? 'Αντιμετάθεση: επιλέγετε τη θέση ενός άλλου εργαλείου· με την αποθήκευση '
            'ανταλλάσσονται οι δύο θέσεις (χωρίς ολίσθηση των ενδιάμεσων). '
            'Η επιλογή Ταξινόμιση/Αντιμετάθεση είναι κοινή για όλα τα εργαλεία (γενική ρύθμιση).'
        : 'Ταξινόμιση: σειρά εμφάνισης· η αποθήκευση τοποθετεί το εργαλείο στη θέση '
            'που επιλέξατε και ολισθαίνει τα υπόλοιπα ώστε να μην υπάρχουν διπλότυπα νούμερα. '
            'Η επιλογή Ταξινόμιση/Αντιμετάθεση είναι κοινή για όλα τα εργαλεία (γενική ρύθμιση).';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                key: ValueKey<Object>(
                  '${swapMode}_${safeMax}_$v',
                ),
                initialValue: v,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Προτεραιότητα',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final i in items)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '$i (${_labelForSortSlot(i)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onChanged == null
                    ? null
                    : (int? x) {
                        if (x != null) onChanged!(x);
                      },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text(
                      'Ταξινόμιση',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text(
                      'Αντιμετάθεση',
                      style: theme.textTheme.labelLarge,
                    ),
                    enabled: swapEnabled,
                  ),
                ],
                selected: {swapMode},
                onSelectionChanged: onSwapModeChanged == null
                    ? null
                    : (Set<bool> next) {
                        final b = next.first;
                        if (b && !swapEnabled) return;
                        onSwapModeChanged!(b);
                      },
                showSelectedIcon: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          helper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ArgRowTile extends StatelessWidget {
  const _ArgRowTile({
    required this.index,
    required this.row,
    required this.onRemove,
    required this.onToggleActive,
    required this.saving,
  });

  final int index;
  final _ArgRow row;
  final VoidCallback onRemove;
  final ValueChanged<bool?> onToggleActive;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_handle,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Checkbox(
                    value: row.active,
                    onChanged: saving ? null : onToggleActive,
                  ),
                  Expanded(
                    child: TextField(
                      controller: row.valueC,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Όρισμα (τιμή)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Διαγραφή',
                    onPressed: saving ? null : onRemove,
                  ),
                ],
              ),
              TextField(
                controller: row.descC,
                enabled: !saving,
                decoration: const InputDecoration(
                  labelText: 'Περιγραφή',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
