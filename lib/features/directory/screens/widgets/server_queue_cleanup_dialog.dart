import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/managed_server.dart';
import '../../../../core/providers/servers_provider.dart';
import '../../../../core/services/server_sessions/server_printer_models.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import 'server_action_banner.dart';

/// Εκκαθάριση των εκκρεμών εκτυπώσεων σε ολόκληρο τον διακομιστή.
///
/// Χρειάζεται ξεχωριστά από την εκκαθάριση ανά σταθμό, γιατί οι ουρές που
/// φουσκώνουν είναι συνήθως **μόνιμων** εκτυπωτών του διακομιστή — όχι
/// ανακατευθυνόμενων. Εκείνοι δεν ανήκουν σε κανέναν σταθμό, οπότε δεν
/// εμφανίζονται ποτέ στον διάλογο του εξοπλισμού.
Future<void> showServerQueueCleanupDialog(
  BuildContext context,
  WidgetRef ref,
  ManagedServer server,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ServerQueueCleanupDialog(server: server),
  );
}

class _ServerQueueCleanupDialog extends ConsumerStatefulWidget {
  const _ServerQueueCleanupDialog({required this.server});

  final ManagedServer server;

  @override
  ConsumerState<_ServerQueueCleanupDialog> createState() =>
      _ServerQueueCleanupDialogState();
}

class _ServerQueueCleanupDialogState
    extends ConsumerState<_ServerQueueCleanupDialog> {
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _done;
  bool _limited = false;

  /// Οι εκτυπωτές που έχουν έστω μία εκκρεμή εκτύπωση.
  List<ServerPrinter> _withQueue = const [];

  /// Ποιων οι ουρές θα αδειάσουν — με το πλήρες όνομα ως κλειδί.
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
      _done = null;
    });

    final s = widget.server;
    final result = await ref
        .read(serverPrinterServiceProvider)
        .listPrinters(
          host: s.host,
          adminUser: s.adminUser,
          adminPassword: s.adminPassword,
        );
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _loading = false;
        _error = result.error;
      });
      return;
    }

    final withQueue = result.printers.where((p) => p.jobCount > 0).toList()
      ..sort((a, b) => b.jobCount.compareTo(a.jobCount));

    setState(() {
      _loading = false;
      _limited = result.isLimited;
      _withQueue = withQueue;
      _selected
        ..clear()
        // Προεπιλέγονται ΜΟΝΟ όσοι δηλώνουν πρόβλημα. Ένας υγιής εκτυπωτής με
        // ουρά τυπώνει αυτή τη στιγμή: εκεί μέσα είναι η δουλειά κάποιου, όχι
        // σκουπίδια.
        ..addAll(
          withQueue
              .where((p) => p.health.needsAttention)
              .map((p) => p.fullName),
        );
    });
  }

  int get _selectedJobs => _withQueue
      .where((p) => _selected.contains(p.fullName))
      .fold(0, (sum, p) => sum + p.jobCount);

  int get _totalJobs => _withQueue.fold(0, (sum, p) => sum + p.jobCount);

  Future<void> _cleanup() async {
    final targets = _withQueue
        .where((p) => _selected.contains(p.fullName))
        .toList();
    if (targets.isEmpty) return;

    final confirmed = await _confirm(targets);
    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });

    final s = widget.server;
    final service = ref.read(serverPrinterServiceProvider);
    var deleted = 0;
    var failed = 0;
    String? lastError;

    for (final p in targets) {
      final result = await service.purgeQueue(
        host: s.host,
        adminUser: s.adminUser,
        adminPassword: s.adminPassword,
        printerFullName: p.fullName,
      );
      if (result.ok) {
        deleted += result.affected;
      } else {
        failed++;
        lastError = result.error;
      }
    }
    if (!mounted) return;

    setState(() {
      _working = false;
      _done = failed == 0
          ? 'Σβήστηκαν $deleted εκτυπώσεις από ${targets.length} εκτυπωτές.'
          : 'Σβήστηκαν $deleted εκτυπώσεις. $failed εκτυπωτές δεν '
                'καθαρίστηκαν.';
      // Η μερική αποτυχία λέγεται, δεν κρύβεται πίσω από τον συνολικό αριθμό.
      _error = failed == 0 ? null : lastError;
    });
    await _scan();
  }

  Future<bool?> _confirm(List<ServerPrinter> targets) {
    final theme = Theme.of(context);
    final healthy = targets.where((p) => !p.health.needsAttention).toList();

    return showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Εκκαθάριση ουρών'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          icon: Icon(
            Icons.warning_amber_outlined,
            color: theme.colorScheme.error,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Να σβηστούν $_selectedJobs εκτυπώσεις από ${targets.length} '
                'εκτυπωτές;',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Χάνονται οριστικά και πρέπει να σταλούν ξανά. Καμία συνεδρία '
                'δεν κλείνει και κανείς δεν πέφτει έξω.',
              ),
              if (healthy.isNotEmpty) ...[
                const SizedBox(height: 12),
                ServerActionBanner(
                  icon: Icons.error_outline,
                  color: theme.colorScheme.error,
                  text:
                      'ΠΡΟΣΟΧΗ: ${healthy.length} από αυτούς δεν δηλώνουν '
                      'πρόβλημα — «${healthy.first.displayName}» και οι '
                      'υπόλοιποι τυπώνουν κανονικά. Εκεί μέσα είναι η δουλειά '
                      'κάποιου, όχι σκουπίδια.',
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Όχι'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ναι, εκκαθάριση'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableDialogShell(
      title: const Text('Εκκαθάριση ουρών εκτυπώσεων'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.server.displayLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(child: _buildBody(theme)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            child: const Text('Κλείσιμο'),
          ),
          OutlinedButton.icon(
            onPressed: _loading || _working ? null : _scan,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Ανανέωση'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: _loading || _working || _selected.isEmpty
                ? null
                : _cleanup,
            icon: _working
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text(
              _working ? 'Γίνεται…' : 'Εκκαθάριση $_selectedJobs εκτυπώσεων',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Σάρωση ουρών…'),
          ],
        ),
      );
    }

    if (_limited) {
      return ServerActionBanner(
        icon: Icons.info_outline,
        color: theme.colorScheme.tertiary,
        text:
            'Δεν μπορούμε να δούμε τις ουρές: η υπηρεσία εκτυπώσεων δεν απαντά '
            'σε αυτόν τον υπολογιστή. Ενεργοποίησε την πλήρη προβολή από την '
            'κάρτα «Κατάσταση αυτού του υπολογιστή».',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_withQueue.isEmpty)
          const Text('Καμία εκκρεμής εκτύπωση σε ολόκληρο τον διακομιστή.')
        else ...[
          Text(
            '$_totalJobs εκκρεμείς εκτυπώσεις σε ${_withQueue.length} '
            'εκτυπωτές. Προεπιλέγονται όσοι δηλώνουν πρόβλημα.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Flexible(
            child: Scrollbar(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _withQueue.length,
                itemBuilder: (ctx, i) => _QueueRow(
                  printer: _withQueue[i],
                  selected: _selected.contains(_withQueue[i].fullName),
                  enabled: !_working,
                  onChanged: (v) => setState(() {
                    if (v) {
                      _selected.add(_withQueue[i].fullName);
                    } else {
                      _selected.remove(_withQueue[i].fullName);
                    }
                  }),
                ),
              ),
            ),
          ),
        ],
        if (_done != null) ...[
          const SizedBox(height: 12),
          ServerActionBanner(
            icon: Icons.check_circle_outline,
            color: theme.colorScheme.primary,
            text: _done!,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          ServerActionBanner(
            icon: Icons.error_outline,
            color: theme.colorScheme.error,
            text: _error!,
          ),
        ],
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.printer,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final ServerPrinter printer;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = printer.health.needsAttention;

    return CheckboxListTile(
      value: selected,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
      title: Text(
        printer.displayName,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${printer.jobCount} εκκρεμείς · ${printer.health.label.toLowerCase()}'
        '${printer.sessionId == null ? ' · εκτυπωτής του διακομιστή' : ' · συνεδρία ${printer.sessionId}'}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: problem
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      secondary: Icon(
        problem ? Icons.print_disabled_outlined : Icons.print_outlined,
        color: problem ? theme.colorScheme.error : null,
      ),
    );
  }
}
