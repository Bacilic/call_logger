import '../../../../core/widgets/dialog_snackbar_scope.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/models/remote_tool_role.dart';
import '../../../../core/utils/file_picker_initial_directory.dart';
import 'remote_tool_arguments_editor.dart';
import 'remote_tool_basic_fields.dart';
import 'remote_tool_behavior_fields.dart';
import 'remote_tool_form_controller.dart';
import 'remote_tool_form_saver.dart';
import 'remote_tool_form_sort.dart';
import 'remote_tool_test_panel.dart';
import '../../../../core/services/portable_tool_image_storage.dart';
import '../../../calls/provider/remote_paths_provider.dart';

enum _SoftDeletedNameChoice { restore, keepSameName }

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

class _RemoteToolFormDialogState extends ConsumerState<RemoteToolFormDialog>
    with DialogSnackbarHost {
  late final RemoteToolFormController _ctrl;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _ctrl = RemoteToolFormController(initialTool: widget.initialTool);
    _ctrl.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickExecutable() async {
    final initial = initialDirectoryForFilePicker(_ctrl.pathC.text);
    final r = await FilePicker.pickFiles(
      type: FileType.any,
      dialogTitle: 'Εκτελέσιμο',
      initialDirectory: initial,
    );
    if (r != null && r.files.isNotEmpty) {
      final p = r.files.single.path;
      if (p != null) {
        _ctrl.pathC.text = p;
      }
    }
  }

  Future<void> _pickIcon() async {
    final initial = initialDirectoryForFilePicker(_ctrl.iconC.text);
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'svg', 'ico'],
      dialogTitle: 'Εικονίδιο εργαλείου',
      initialDirectory: initial,
    );
    if (r == null || r.files.isEmpty) return;
    final picked = r.files.single.path;
    if (picked == null) return;
    if (!mounted) return;

    final copyToPortable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αντιγραφή εικονιδίου'),
        content: const Text(
          'Να αντιγραφεί το εικονίδιο στον φάκελο images της εφαρμογής;\n'
          'Αυτό ενισχύει τη φορητότητα της εφαρμογής και συμβάλλει στην '
          'επαναφορά από αντίγραφο ασφαλείας.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Όχι, κράτα την τρέχουσα θέση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Αντιγραφή'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (copyToPortable == true) {
      try {
        _ctrl.iconC.text =
            await PortableToolImageStorage.copyPickedIconToPortable(picked);
      } catch (e) {
        if (mounted) {
          showDialogSnackBar(
            SnackBar(content: Text('Αποτυχία αντιγραφής εικονιδίου: $e')),
          );
        }
        _ctrl.iconC.text = picked;
      }
    } else {
      _ctrl.iconC.text = picked;
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


  /// Επαναφορά soft-deleted γραμμής με τα περιεχόμενα της φόρμας· σε επεξεργασία
  /// άλλου id, η τρέχουσα εγγραφή διαγράφεται (soft).
  Future<void> _saveRestoringSoftDeleted(
    RemoteToolFormSaver saver,
    RemoteTool softDeleted,
  ) async {
    await saver.commitRestoreSoftDeleted(
      toolFromForm: _ctrl.toRemoteTool(id: softDeleted.id),
      editCurrentIdToDelete:
          _ctrl.isEdit && widget.initialTool!.id != softDeleted.id
              ? widget.initialTool!.id
              : null,
    );
    _invalidateRemote();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final repo = ref.read(remoteToolsRepositoryProvider);
    final saver = RemoteToolFormSaver(repo);
    final all = await saver.loadNonDeleted();
    final err = _ctrl.validateName(all);
    if (err != null) {
      if (mounted) {
        showDialogSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final nameTrim = _ctrl.nameC.text.trim();
    final softDeleted = await saver.findSoftDeletedConflict(
      nameTrim,
      excludeId: _ctrl.isEdit ? widget.initialTool!.id : null,
    );
    if (softDeleted != null) {
      final choice = await _showSoftDeletedNameConflictDialog(softDeleted);
      if (!mounted) return;
      if (choice == null) return;
      if (choice == _SoftDeletedNameChoice.restore) {
        _ctrl.saving = true;
        _ctrl.refresh();
        try {
          await _saveRestoringSoftDeleted(saver, softDeleted);
        } catch (e) {
          if (mounted) {
            showDialogSnackBar(
              SnackBar(
                content: Text('Σφάλμα: $e'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        } finally {
          if (mounted) {
            _ctrl.saving = false;
            _ctrl.refresh();
          }
        }
        return;
      }
      await saver.disambiguateSoftDeleted(softDeleted.id);
    }

    _ctrl.saving = true;
    _ctrl.refresh();
    try {
      if (_ctrl.isEdit) {
        await saver.commitEdit(
          toolFromForm: _ctrl.toRemoteTool(id: widget.initialTool!.id),
        );
      } else {
        await saver.commitNew(
          toolFromForm: _ctrl.toRemoteTool(id: 0),
        );
      }
      _invalidateRemote();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showDialogSnackBar(
          SnackBar(
            content: Text('Σφάλμα: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        _ctrl.saving = false;
        _ctrl.refresh();
      }
    }
  }

  void _invalidateRemote() {
    ref.invalidate(remoteToolsAllCatalogProvider);
    ref.invalidate(remoteToolsCatalogProvider);
    ref.invalidate(remoteToolFormPairsProvider);
    ref.invalidate(remotePathsProvider);
    ref.invalidate(validRemoteToolPathsByIdProvider);
    ref.invalidate(remoteLauncherStatusesByIdProvider);
  }

  Future<void> _runTest() async {
    final id = widget.initialTool?.id ?? 0;
    final tool = _ctrl.toRemoteTool(id: id);
    try {
      await ref.read(remoteLauncherServiceProvider).testRemoteTool(tool);
      if (mounted) {
        showDialogSnackBar(
          const SnackBar(
            content: Text(
              'Η δοκιμή ξεκίνησε (ενεργά ορίσματα + δοκιμαστικός στόχος).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialogSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _onRoleChanged(ToolRole v) async {
    final prev = _ctrl.role;
    _ctrl.role = v;
    _ctrl.refresh();
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
      _ctrl.applyRolePreset(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);
    final asyncTools = ref.watch(remoteToolsAllCatalogProvider);

    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: asyncTools.when(
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
                    _ctrl.isEdit
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
                          NameAutocompleteField(
                            controller: _ctrl.nameC,
                            focusNode: _ctrl.nameFocus,
                            suggestions: nameSuggestions,
                            excludeId:
                                _ctrl.isEdit ? widget.initialTool!.id : null,
                            nonDeleted: nonDeleted,
                            isCreate: !_ctrl.isEdit,
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
                            value: _ctrl.isActive,
                            onChanged: _ctrl.saving
                                ? null
                                : (v) {
                                    _ctrl.isActive = v;
                                    _ctrl.refresh();
                                  },
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(theme, 'Εκτέλεση'),
                          const Divider(),
                          ExecutablePathField(
                            controller: _ctrl.pathC,
                            onPick: _pickExecutable,
                            enabled: !_ctrl.saving,
                            isCreate: !_ctrl.isEdit,
                          ),
                          const SizedBox(height: 12),
                          LaunchModeSelector(
                            value: _ctrl.launchMode,
                            onChanged: _ctrl.saving
                                ? null
                                : (v) {
                                    _ctrl.launchMode = v;
                                    _ctrl.refresh();
                                  },
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(theme, 'Εικονίδιο εργαλείου'),
                          const Divider(),
                          IconFieldWithPreview(
                            controller: _ctrl.iconC,
                            onPick: _pickIcon,
                            enabled: !_ctrl.saving,
                          ),
                          const SizedBox(height: 16),
                          _sectionTitle(theme, 'Συμπεριφορά και Ρόλος'),
                          const Divider(),
                          RoleDropdown(
                            value: _ctrl.role,
                            onChanged: _ctrl.saving
                                ? null
                                : (v) => _onRoleChanged(v),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PopupMenuButton<ToolRole>(
                              enabled: !_ctrl.saving,
                              tooltip: 'Προεπιλογές ρόλου',
                              onSelected: (r) {
                                if (!_ctrl.saving) _ctrl.applyRolePreset(r);
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
                          _sectionTitle(theme, 'Ορίσματα γραμμής εντολών'),
                          const Divider(),
                          RemoteToolArgumentsEditor(controller: _ctrl),
                          const SizedBox(height: 16),
                          RemoteToolTestPanel(
                            controller: _ctrl,
                            onRunTest: _runTest,
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
                        onPressed: _ctrl.saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Ακύρωση'),
                      ),
                      const SizedBox(width: 8),
                      _ctrl.isEdit
                          ? FilledButton(
                              onPressed: _ctrl.canSubmitSave ? _save : null,
                              child: _ctrl.saving
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
                              message: _ctrl.createPrimaryButtonTooltip(),
                              waitDuration:
                                  const Duration(milliseconds: 400),
                              child: FilledButton(
                                onPressed: _ctrl.canSubmitSave ? _save : null,
                                child: _ctrl.saving
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
    ),
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
