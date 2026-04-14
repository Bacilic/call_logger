import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/models/remote_tool.dart';
import '../../calls/provider/remote_paths_provider.dart';
import '../../../core/services/settings_service.dart';
import '../widgets/remote_tool_form_dialog.dart';

/// Προεπισκόπηση εικονιδίου στη λίστα (asset, διαδρομή αρχείου ή asset key) — συμβατό με `iconAssetKey`.
Widget _remoteToolListIcon(RemoteTool t, {double size = 22}) {
  final raw = t.iconAssetKey?.trim() ?? '';
  if (raw.isEmpty) return const SizedBox.shrink();
  Widget broken() => Icon(Icons.broken_image_outlined, size: size);
  if (raw.startsWith('assets/')) {
    return Image.asset(
      raw,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => broken(),
    );
  }
  final f = File(raw);
  if (f.existsSync()) {
    return Image.file(
      f,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => broken(),
    );
  }
  return Image.asset(
    raw,
    width: size,
    height: size,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stackTrace) => broken(),
  );
}

/// CRUD ορισμών `remote_tools` + ρυθμίσεις κύριου εργαλείου / overflow στην οθόνη κλήσεων.
class RemoteToolsManagementScreen extends ConsumerStatefulWidget {
  const RemoteToolsManagementScreen({
    super.key,
    this.embedded = false,
    this.onBackToDashboard,
  });

  /// Όταν true (π.χ. μέσα στο hub «Διάφορα»), κρύβεται το [AppBar] — η πλοήγηση γίνεται από τον γονέα.
  final bool embedded;
  final VoidCallback? onBackToDashboard;

  @override
  ConsumerState<RemoteToolsManagementScreen> createState() =>
      _RemoteToolsManagementScreenState();
}

class _RemoteToolsManagementScreenState
    extends ConsumerState<RemoteToolsManagementScreen> {
  final ScrollController _pageScrollController = ScrollController();

  late Future<Map<int, int>> _equipmentUsageFuture;

  @override
  void initState() {
    super.initState();
    _equipmentUsageFuture = _fetchEquipmentUsage();
  }

  Future<Map<int, int>> _fetchEquipmentUsage() async {
    final db = await DatabaseHelper.instance.database;
    return DirectoryRepository(db).getEquipmentDefaultRemoteToolUsageCounts();
  }

  void _refreshEquipmentUsage() {
    setState(() {
      _equipmentUsageFuture = _fetchEquipmentUsage();
    });
  }

  /// Κείμενο tooltip στήλης ονόματος: πόσοι εξοπλισμοί έχουν προεπιλογή αυτού του id.
  String _tooltipForToolUsage(int n) {
    if (n <= 0) {
      return 'Δεν είναι ορισμένο ως προεπιλογή σε κανέναν εξοπλισμό.';
    }
    if (n == 1) {
      return 'Ενεργοποιημένο σε 1 εξοπλισμό.';
    }
    return 'Ενεργοποιημένο σε $n εξοπλισμούς.';
  }

  void _invalidateRemoteCatalog() {
    ref.invalidate(remoteToolsAllCatalogProvider);
    ref.invalidate(remoteToolsCatalogProvider);
    ref.invalidate(remoteToolFormPairsProvider);
    ref.invalidate(remotePathsProvider);
    ref.invalidate(validRemoteToolPathsByIdProvider);
    ref.invalidate(validRemotePathsProvider);
    ref.invalidate(remoteLauncherStatusesByIdProvider);
    ref.invalidate(remoteLauncherStatusProvider);
  }

  String _argumentsSummary(RemoteTool t) {
    final active = t.arguments.where((a) => a.isActive).toList();
    if (active.isEmpty) return '—';
    final parts = active.take(2).map((a) => a.value).toList();
    var s = parts.join(', ');
    if (active.length > 2) s = '$s…';
    if (s.length > 80) s = '${s.substring(0, 77)}…';
    return s;
  }

  Future<void> _setToolActive(RemoteTool t, bool value) async {
    if (!value && t.isActive) {
      final counts = await _fetchEquipmentUsage();
      final n = counts[t.id] ?? 0;
      if (n > 0 && mounted) {
        final theme = Theme.of(context);
        final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Απενεργοποίηση εργαλείου'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if ((t.iconAssetKey?.trim() ?? '').isNotEmpty) ...[
                        _remoteToolListIcon(t, size: 32),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          '«${t.name}»',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    n == 1
                        ? 'Το παραπάνω εργαλείο είναι ενεργοποιημένο σε 1 εξοπλισμό. '
                            'Να απενεργοποιηθεί;'
                        : 'Το παραπάνω εργαλείο είναι ενεργοποιημένο σε $n εξοπλισμούς. '
                            'Να απενεργοποιηθεί;',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Οι ρυθμίσεις δεν θα χαθούν· θα επανέλθουν με την ενεργοποίηση του '
                    'εργαλείου «${t.name}».',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Ακύρωση'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Απενεργοποίηση'),
              ),
            ],
          ),
        );
        if (confirm != true || !mounted) {
          return;
        }
      }
    }
    try {
      final repo = ref.read(remoteToolsRepositoryProvider);
      await repo.updateTool(t.copyWith(isActive: value));
      _invalidateRemoteCatalog();
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

  Future<void> _openToolEditor(RemoteTool t) async {
    final saved =
        await showRemoteToolFormDialog(context, ref, tool: t);
    if (!mounted) return;
    if (saved == true) {
      _refreshEquipmentUsage();
    }
  }

  static const String _cloneNameSuffix = ' (αντίγραφο)';

  /// Μοναδικό όνομα «… (αντίγραφο)» ή «… (αντίγραφο 2)» κ.λπ.
  String _uniqueCloneName(String baseName, List<RemoteTool> nonDeleted) {
    final taken = nonDeleted
        .map((e) => e.name.trim().toLowerCase())
        .toSet();
    final trimmed = baseName.trim();
    var candidate = '$trimmed$_cloneNameSuffix';
    if (!taken.contains(candidate.toLowerCase())) return candidate;
    var i = 2;
    while (true) {
      candidate = '$trimmed$_cloneNameSuffix $i';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
      i++;
    }
  }

  Future<void> _cloneTool(RemoteTool t) async {
    try {
      final repo = ref.read(remoteToolsRepositoryProvider);
      final existing = await repo.getAllNonDeletedTools();
      final name = _uniqueCloneName(t.name, existing);
      final n = existing.length;
      final clone = t.copyWith(
        id: 0,
        name: name,
        clearDeletedAt: true,
      );
      final newId = await repo.insertTool(clone);
      await repo.reorderToolToPosition(
        toolId: newId,
        positionOneBased: n + 1,
      );
      _invalidateRemoteCatalog();
      _refreshEquipmentUsage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Δημιουργήθηκε το αντίγραφο «$name».')),
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

  Future<void> _softDeleteTool(RemoteTool t) async {
    final counts = await _fetchEquipmentUsage();
    final n = counts[t.id] ?? 0;
    if (!mounted) return;
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Απομάκρυνση εργαλείου'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              n == 0
                  ? 'Να απομακρυνθεί από τη λίστα το εργαλείο «${t.name}»;'
                  : n == 1
                      ? 'Το εργαλείο «${t.name}» είναι ορισμένο ως προεπιλογή σε 1 εξοπλισμό. '
                          'Να απομακρυνθεί από τη λίστα;'
                      : 'Το εργαλείο «${t.name}» είναι ορισμένο ως προεπιλογή σε $n εξοπλισμούς. '
                          'Να απομακρυνθεί από τη λίστα;',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Η εγγραφή δεν διαγράφεται οριστικά· οι αναφορές εξοπλισμού (id) παραμένουν για συμβατότητα.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Απομάκρυνση'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final repo = ref.read(remoteToolsRepositoryProvider);
      await repo.deleteTool(t.id);
      _invalidateRemoteCatalog();
      _refreshEquipmentUsage();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Απομακρύνθηκε το εργαλείο «${t.name}».'),
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

  @override
  void dispose() {
    _pageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(remoteToolsAllCatalogProvider);
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Απομακρυσμένα εργαλεία'),
            ),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RemoteConnectionSettingsPanel(
              onBackToDashboard: widget.onBackToDashboard,
              onAfterRemoteToolSaved: _refreshEquipmentUsage,
            ),
            SizedBox(height: 32),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RemoteConnectionSettingsPanel(
              onBackToDashboard: widget.onBackToDashboard,
              onAfterRemoteToolSaved: _refreshEquipmentUsage,
            ),
            const SizedBox(height: 24),
            Center(child: Text('$e')),
          ],
        ),
        data: (allTools) {
          final tools =
              allTools.where((t) => t.deletedAt == null).toList();
          return FutureBuilder<Map<int, int>>(
            future: _equipmentUsageFuture,
            builder: (context, snapshot) {
              final usage = snapshot.data;
              return Scrollbar(
          controller: _pageScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _pageScrollController,
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _RemoteConnectionSettingsPanel(
                    onBackToDashboard: widget.onBackToDashboard,
                    onAfterRemoteToolSaved: _refreshEquipmentUsage,
                  ),
                ),
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Εργαλεία',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: DataTable(
                          headingRowHeight: 40,
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 64,
                          columns: const [
                            DataColumn(label: Text('Ενεργό')),
                            DataColumn(label: Text('Όνομα')),
                            DataColumn(label: Text('Εκτελέσιμο')),
                            DataColumn(label: Text('Ορίσματα (ενεργά)')),
                            DataColumn(label: Text('Ενέργειες')),
                          ],
                          rows: [
                            for (final t in tools)
                              DataRow(
                                key: ValueKey(t.id),
                                cells: [
                                  DataCell(
                                    Switch.adaptive(
                                      value: t.isActive,
                                      onChanged: (v) =>
                                          _setToolActive(t, v),
                                    ),
                                  ),
                                  DataCell(
                                    Tooltip(
                                      message: usage == null
                                          ? 'Φόρτωση…'
                                          : _tooltipForToolUsage(
                                              usage[t.id] ?? 0,
                                            ),
                                      waitDuration:
                                          const Duration(milliseconds: 400),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onDoubleTap: () =>
                                            _openToolEditor(t),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 220,
                                          ),
                                          child: Row(
                                            children: [
                                              if ((t.iconAssetKey
                                                          ?.trim() ??
                                                      '')
                                                  .isNotEmpty) ...[
                                                _remoteToolListIcon(t),
                                                const SizedBox(width: 8),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  t.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onDoubleTap: () =>
                                          _openToolEditor(t),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 280,
                                        ),
                                        child: Text(
                                          t.executablePath,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontFamily: 'monospace',
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onDoubleTap: () =>
                                          _openToolEditor(t),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 260,
                                        ),
                                        child: Text(
                                          _argumentsSummary(t),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Επεξεργασία',
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                          ),
                                          onPressed: () =>
                                              _openToolEditor(t),
                                        ),
                                        IconButton(
                                          tooltip:
                                              'Αντίγραφο (ίδιες ρυθμίσεις, νέο όνομα με «$_cloneNameSuffix»)',
                                          icon: const Icon(
                                            Icons.copy_outlined,
                                          ),
                                          onPressed: () => _cloneTool(t),
                                        ),
                                        IconButton(
                                          tooltip:
                                              'Απομάκρυνση από τη λίστα (soft delete)',
                                          icon: Icon(
                                            Icons.delete_outline,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                          onPressed: () =>
                                              _softDeleteTool(t),
                                        ),
                                      ],
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Οθόνη κλήσεων',
                        style:
                            Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _CallsRemoteUiPanel(tools: tools),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
            },
          );
        },
      ),
    );
  }
}

class _RemoteConnectionSettingsPanel extends ConsumerStatefulWidget {
  const _RemoteConnectionSettingsPanel({
    this.onBackToDashboard,
    this.onAfterRemoteToolSaved,
  });

  final VoidCallback? onBackToDashboard;
  /// Μετά από αποθήκευση από φόρμα εργαλείου (προσθήκη) — ανανέωση μετρήσεων εξοπλισμού.
  final VoidCallback? onAfterRemoteToolSaved;

  @override
  ConsumerState<_RemoteConnectionSettingsPanel> createState() =>
      _RemoteConnectionSettingsPanelState();
}

class _RemoteConnectionSettingsPanelState
    extends ConsumerState<_RemoteConnectionSettingsPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (widget.onBackToDashboard != null) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Επιστροφή στα Διάφορα',
                onPressed: widget.onBackToDashboard,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                'Ρυθμίσεις απομακρυσμένης σύνδεσης',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip:
                  'Προσθήκη νέου εργαλείου απομακρυσμένης σύνδεσης',
              onPressed: () async {
                final saved = await showRemoteToolFormDialog(
                  context,
                  ref,
                  tool: null,
                );
                if (saved == true) {
                  widget.onAfterRemoteToolSaved?.call();
                }
              },
              icon: Image.asset(
                'assets/add_remote_tool_icon.png',
                width: 28,
                height: 28,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Οι διαδρομές εκτελέσιμων, τα ορίσματα ανά εργαλείο και το πρότυπο .rdp '
          'διαχειρίζονται στον πίνακα παρακάτω. Ο κωδικός πρόσβασης (VNC / RDP κλπ.) '
          'και η δοκιμαστική IP για «Δοκιμή εργαλείου» ορίζονται ανά εργαλείο από τη '
          'φόρμα επεξεργασίας.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CallsRemoteUiPanel extends ConsumerStatefulWidget {
  const _CallsRemoteUiPanel({required this.tools});

  final List<RemoteTool> tools;

  @override
  ConsumerState<_CallsRemoteUiPanel> createState() => _CallsRemoteUiPanelState();
}

class _CallsRemoteUiPanelState extends ConsumerState<_CallsRemoteUiPanel> {
  int? _primaryId;
  bool _overflow = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = SettingsService();
    final p = await s.getCallsPrimaryToolId();
    final o = await s.getCallsShowSecondaryRemoteActions();
    if (mounted) {
      setState(() {
        _primaryId = p;
        _overflow = o;
        _loaded = true;
      });
    }
  }

  Future<void> _onPrimaryToolChanged(int? v) async {
    final previous = _primaryId;
    setState(() => _primaryId = v);
    try {
      await SettingsService().setCallsPrimaryToolId(v);
      ref.invalidate(callsRemoteUiConfigProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _primaryId = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Αποθήκευση κύριου εργαλείου: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _onOverflowChanged(bool v) async {
    final previous = _overflow;
    setState(() => _overflow = v);
    try {
      await SettingsService().setCallsShowSecondaryRemoteActions(v);
      ref.invalidate(callsRemoteUiConfigProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _overflow = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Αποθήκευση overflow: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final active = widget.tools.where((t) => t.isActive).toList();
    if (active.isEmpty) {
      return Text(
        'Δεν υπάρχουν ενεργά εργαλεία — ενεργοποιήστε εργαλεία στον πίνακα παραπάνω.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int?>(
          key: ValueKey<int?>(_primaryId),
          initialValue: _primaryId,
          decoration: const InputDecoration(
            labelText: 'Κύριο κουμπί (null = πρώτο ενεργό)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Αυτόματο (πρώτο ενεργό)'),
            ),
            ...active.map(
              (t) => DropdownMenuItem<int?>(
                value: t.id,
                child: Text(t.name),
              ),
            ),
          ],
          onChanged: (v) => _onPrimaryToolChanged(v),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Δευτερεύοντα σε μενού overflow'),
          subtitle: const Text(
            'Όταν είναι ενεργό, επιπλέον εργαλεία ανοίγουν από το εικονίδιο «⋯».',
          ),
          value: _overflow,
          onChanged: (v) => _onOverflowChanged(v),
        ),
      ],
    );
  }
}
