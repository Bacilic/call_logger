import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/managed_server.dart';
import '../../../../core/providers/servers_provider.dart';
import '../../../../core/services/server_sessions/server_session_models.dart';
import '../../../../core/services/server_sessions/smb1_client_status.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../../../core/widgets/section_card.dart';
import 'server_form_dialog.dart';
import 'server_maintenance_actions.dart';

/// Οθόνη «Διακομιστές» (Κατάλογος → Διάφορα).
///
/// Σκόπιμα **γενική**: κρατά μηχανήματα με στοιχεία διαχειριστή, χωρίς να
/// γνωρίζει σε τι χρησιμεύουν. Η πρώτη λειτουργία που τα χρησιμοποιεί είναι η
/// «Αποσύνδεση χρήστη» από τις κλήσεις· όποια προστεθεί αργότερα (π.χ.
/// επανεκκίνηση) διαβάζει την ίδια λίστα.
class ServersManagementView extends ConsumerStatefulWidget {
  const ServersManagementView({super.key});

  @override
  ConsumerState<ServersManagementView> createState() =>
      _ServersManagementViewState();
}

class _ServersManagementViewState extends ConsumerState<ServersManagementView> {
  Future<void> _add() async {
    final saved = await showServerFormDialog(context);
    if (saved) ref.invalidate(serversListProvider);
  }

  Future<void> _edit(ManagedServer server) async {
    final saved = await showServerFormDialog(context, server: server);
    if (saved) ref.invalidate(serversListProvider);
  }

  Future<void> _delete(ManagedServer server) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Αφαίρεση διακομιστή'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          content: Text(
            'Να αφαιρεθεί ο «${server.name}» (${server.host});\n\n'
            'Οι λειτουργίες που τον χρησιμοποιούν δεν θα τον βρίσκουν πια.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Αφαίρεση'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(serversRepositoryProvider).softDelete(server.id);
      ref.invalidate(serversListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Αφαιρέθηκε ο διακομιστής «${server.name}».')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Αποτυχία αφαίρεσης: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(serversListProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => SectionCard(
                  icon: Icons.error_outline,
                  title: 'Διακομιστές',
                  child: Text('Αποτυχία φόρτωσης: $e'),
                ),
                data: _buildList,
              ),
              const SizedBox(height: 16),
              const _Smb1StatusCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<ManagedServer> servers) {
    return SectionCard(
      icon: Icons.dns_outlined,
      title: 'Διακομιστές',
      trailing: FilledButton.tonalIcon(
        onPressed: _add,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Προσθήκη'),
      ),
      child: servers.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Δεν υπάρχει κανένας καταχωρημένος διακομιστής. Πρόσθεσε έναν '
                'για να μπορεί η εφαρμογή να αποσυνδέει χρήστες.',
              ),
            )
          : Column(
              children: [
                for (final s in servers)
                  _ServerRow(
                    server: s,
                    onEdit: () => _edit(s),
                    onDelete: () => _delete(s),
                    onRestartSpooler: () =>
                        showRestartSpoolerDialog(context, ref, s),
                    onCleanOrphans: () =>
                        showOrphanCleanupDialog(context, ref, s),
                    onRestartServer: () =>
                        showServerRestartDialog(context, ref, s),
                  ),
              ],
            ),
    );
  }
}

enum _ServerRowAction {
  edit,
  restartSpooler,
  cleanOrphans,
  restartServer,
  delete,
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.onEdit,
    required this.onDelete,
    required this.onRestartSpooler,
    required this.onCleanOrphans,
    required this.onRestartServer,
  });

  final ManagedServer server;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRestartSpooler;
  final VoidCallback onCleanOrphans;
  final VoidCallback onRestartServer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missingPassword = server.adminPassword.isEmpty;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onEdit,
      leading: Icon(
        Icons.dns_outlined,
        color: server.isDefault ? theme.colorScheme.primary : null,
      ),
      title: Row(
        children: [
          Flexible(child: Text(server.name, overflow: TextOverflow.ellipsis)),
          if (server.isDefault) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'προεπιλογή',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          Text('${server.host} · ${server.adminUser}'),
          if (missingPassword) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.key_off_outlined,
              size: 15,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 4),
            Text(
              'χωρίς κωδικό',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      trailing: PopupMenuButton<_ServerRowAction>(
        tooltip: 'Ενέργειες',
        icon: const Icon(Icons.more_vert),
        onSelected: (action) => switch (action) {
          _ServerRowAction.edit => onEdit(),
          _ServerRowAction.restartSpooler => onRestartSpooler(),
          _ServerRowAction.cleanOrphans => onCleanOrphans(),
          _ServerRowAction.restartServer => onRestartServer(),
          _ServerRowAction.delete => onDelete(),
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(
            value: _ServerRowAction.edit,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined),
              title: Text('Επεξεργασία'),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _ServerRowAction.restartSpooler,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.print_outlined),
              title: Text('Επανεκκίνηση ουράς εκτυπώσεων'),
              subtitle: Text(
                'Δεν πέφτει κανείς έξω',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          const PopupMenuItem(
            value: _ServerRowAction.cleanOrphans,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cleaning_services_outlined),
              title: Text('Καθαρισμός ορφανών εκτυπωτών'),
              subtitle: Text(
                'Αφαιρεί ό,τι έμεινε από κλειστές συνεδρίες',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _ServerRowAction.restartServer,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.restart_alt, color: theme.colorScheme.error),
              title: Text(
                'Επανεκκίνηση διακομιστή…',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: const Text(
                'Πέφτουν έξω ΟΛΟΙ οι συνδεδεμένοι',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _ServerRowAction.delete,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline),
              title: Text('Αφαίρεση από τη λίστα'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Κατάσταση του SMB1 σε αυτόν τον υπολογιστή.
///
/// Στέκεται εδώ και όχι σε κάποιο κρυφό διαγνωστικό, γιατί όταν λείπει, κάθε
/// διακομιστής του 2003 μοιάζει «να μην απαντά» — και η αιτία δεν είναι
/// μαντέψιμη από το μήνυμα σφάλματος.
class _Smb1StatusCard extends ConsumerWidget {
  const _Smb1StatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(smb1ClientStatusProvider);

    return SectionCard(
      icon: Icons.computer_outlined,
      title: 'Κατάσταση αυτού του υπολογιστή',
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Γίνεται έλεγχος…'),
            ],
          ),
        ),
        error: (e, _) => Text('Αποτυχία ελέγχου: $e'),
        data: (status) {
          final problem = status.isProblem;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (status) {
                      Smb1ClientStatus.running => Icons.check_circle_outline,
                      Smb1ClientStatus.unknown => Icons.help_outline,
                      _ => Icons.warning_amber_outlined,
                    },
                    size: 18,
                    color: problem
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(status.label)),
                ],
              ),
              if (problem) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text(
                      'Άνοιγμα «Δυνατότητες των Windows» (SMB 1.0/CIFS)',
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final opened = await openWindowsOptionalFeatures();
                      if (!context.mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            opened
                                ? 'Άνοιξε το παράθυρο δυνατοτήτων. Μετά την '
                                      'αλλαγή χρειάζεται επανεκκίνηση του '
                                      'υπολογιστή.'
                                : 'Δεν ήταν δυνατό το άνοιγμα του παραθύρου '
                                      'δυνατοτήτων των Windows.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
