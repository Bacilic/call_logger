import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/managed_server.dart';
import '../../../../core/providers/servers_provider.dart';
import '../../../../core/services/server_sessions/logoff_target_resolution.dart';
import '../../../../core/services/server_sessions/server_session_models.dart';
import '../../../../core/widgets/draggable_dialog_shell.dart';
import '../../utils/equipment_server_context.dart';

/// Ανοίγει τον διάλογο «Αποσύνδεση χρήστη» για έναν κωδικό εξοπλισμού.
Future<void> showUserLogoffDialog(
  BuildContext context, {
  required String equipmentCode,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _UserLogoffDialog(equipmentCode: equipmentCode),
  );
}

class _UserLogoffDialog extends ConsumerStatefulWidget {
  const _UserLogoffDialog({required this.equipmentCode});

  final String equipmentCode;

  @override
  ConsumerState<_UserLogoffDialog> createState() => _UserLogoffDialogState();
}

class _UserLogoffDialogState extends ConsumerState<_UserLogoffDialog> {
  /// Ο διακομιστής που ρωτάμε τώρα. Ο χειριστής μπορεί να τον αλλάξει.
  ManagedServer? _server;

  /// Γιατί προτάθηκε αυτός ο διακομιστής — φαίνεται κάτω από τον επιλογέα.
  ServerTargetChoice? _choice;

  List<ManagedServer> _servers = const [];
  LogoffSessionPlan? _plan;
  int? _selectedSessionId;

  bool _loading = true;
  bool _working = false;
  String? _error;

  /// Το όνομα σταθμού που αντιστοιχεί σε αυτόν τον εξοπλισμό (π.χ. `PC3414`).
  String _stationName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// Πρώτο πέρασμα: ποιον διακομιστή ρωτάμε και ποιο είναι το PC του εξοπλισμού.
  Future<void> _bootstrap() async {
    final context = await resolveEquipmentServerContext(
      ref,
      widget.equipmentCode,
    );
    if (!mounted) return;

    _stationName = context.stationName;
    final choice = context.choice;

    setState(() {
      _servers = context.servers;
      _choice = choice;
      _server = choice.server;
    });

    if (choice.server == null) {
      setState(() {
        _loading = false;
        _error =
            'Δεν υπάρχει καταχωρημένος διακομιστής. Πρόσθεσε έναν από τον '
            'Κατάλογο → Διάφορα → Διακομιστές.';
      });
      return;
    }
    await _refresh();
  }

  /// Ρωτάει τον διακομιστή και ξαναχτίζει την πρόταση.
  Future<void> _refresh() async {
    final server = _server;
    if (server == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _plan = null;
    });

    final result = await ref
        .read(serverSessionServiceProvider)
        .listSessions(
          host: server.host,
          adminUser: server.adminUser,
          adminPassword: server.adminPassword,
        );
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _loading = false;
        _error = result.error;
      });
      return;
    }

    final plan = LogoffTargetResolution.buildPlan(
      sessions: result.sessions,
      equipmentStationName: _stationName,
      adminUser: server.adminUser,
    );
    setState(() {
      _loading = false;
      _plan = plan;
      _selectedSessionId = plan.preselectedSessionId;
    });
  }

  Future<void> _logoff() async {
    final server = _server;
    final sessionId = _selectedSessionId;
    final plan = _plan;
    if (server == null || sessionId == null || plan == null) return;

    final candidate = plan.candidates.firstWhere(
      (c) => c.session.sessionId == sessionId,
    );
    final confirmed = await _confirm(candidate, server);
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final result = await ref
        .read(serverSessionServiceProvider)
        .logoff(
          host: server.host,
          adminUser: server.adminUser,
          adminPassword: server.adminPassword,
          sessionId: sessionId,
        );
    if (!mounted) return;
    setState(() => _working = false);

    if (!result.ok) {
      setState(() => _error = result.error);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Η συνεδρία του «${candidate.session.username}» τερματίστηκε στον '
          '${server.host}.',
        ),
      ),
    );
  }

  /// Αποσυνδέει την οθόνη: η συνεδρία μένει ζωντανή.
  ///
  /// Το φθηνό σκαλί για το συνηθέστερο πρόβλημα — «δεν φορτώθηκαν οι
  /// εκτυπωτές». Ο χρήστης ξανασυνδέεται και ο υπολογιστής του τους
  /// ξαναστέλνει, χωρίς να κλείσει τίποτα.
  Future<void> _disconnect() async {
    final server = _server;
    final sessionId = _selectedSessionId;
    final plan = _plan;
    if (server == null || sessionId == null || plan == null) return;

    final candidate = plan.candidates.firstWhere(
      (c) => c.session.sessionId == sessionId,
    );
    final confirmed = await _confirmDisconnect(candidate, server);
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final result = await ref
        .read(serverSessionServiceProvider)
        .disconnect(
          host: server.host,
          adminUser: server.adminUser,
          adminPassword: server.adminPassword,
          sessionId: sessionId,
        );
    if (!mounted) return;
    setState(() => _working = false);

    if (!result.ok) {
      setState(() => _error = result.error);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Η οθόνη του «${candidate.session.username}» αποσυνδέθηκε. Η εργασία '
          'του συνεχίζει — ας ξανασυνδεθεί για να φορτώσουν οι εκτυπωτές.',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  /// Επιβεβαίωση αποσύνδεσης οθόνης — ήπια, γιατί τίποτα δεν χάνεται.
  ///
  /// Σε αντίθεση με τον τερματισμό, εδώ προεπιλέγεται το «Ναι»: η ενέργεια
  /// είναι αναστρέψιμη με μια επανασύνδεση, και η προεπιλογή «Όχι» θα
  /// υπονοούσε κίνδυνο που δεν υπάρχει.
  Future<bool?> _confirmDisconnect(
    LogoffCandidate candidate,
    ManagedServer server,
  ) {
    final theme = Theme.of(context);
    final s = candidate.session;
    final from = s.stationName.trim().isEmpty
        ? ''
        : ' του σταθμού ${s.stationName}';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Αποσύνδεση οθόνης'),
        builder: (titleHandle) => AlertDialog(
          title: titleHandle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Να αποσυνδεθεί η οθόνη του «${s.username}»$from;',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Το medico ΔΕΝ κλείνει και τίποτα δεν χάνεται — η εργασία '
                'συνεχίζει να τρέχει στον διακομιστή. Ο χρήστης απλώς χάνει '
                'την εικόνα και ξανασυνδέεται με διπλό κλικ στη συντόμευσή του.',
              ),
              const SizedBox(height: 12),
              Text(
                'Στην επανασύνδεση, ο υπολογιστής του ξαναστέλνει τους '
                'εκτυπωτές του στον διακομιστή.',
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
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Αποσύνδεση οθόνης'),
            ),
          ],
        ),
      ),
    );
  }

  /// Επιβεβαίωση με προεπιλογή το «Όχι» — η ενέργεια δεν αναιρείται.
  Future<bool?> _confirm(LogoffCandidate candidate, ManagedServer server) {
    final theme = Theme.of(context);
    final s = candidate.session;
    final from = s.stationName.trim().isEmpty
        ? ''
        : ' από τον σταθμό ${s.stationName}';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => DraggableDialogShell(
        title: const Text('Τερματισμός συνεδρίας'),
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
                'Να τερματιστεί η συνεδρία του «${s.username}»$from στον '
                '${server.host};',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Η συνεδρία κλείνει εντελώς. Ό,τι δεν έχει αποθηκευτεί μέσα '
                'στο medico θα χαθεί.',
              ),
              if (candidate.isAdminAccount) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      'ΠΡΟΣΟΧΗ: είναι η συνεδρία του ίδιου του λογαριασμού '
                      'διαχειριστή που χρησιμοποιεί η εφαρμογή. Πιθανότατα '
                      'δουλεύει κάποιος συνάδελφος πάνω της.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
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
              child: const Text('Ναι, τερματισμός'),
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
      title: Text('Αποσύνδεση χρήστη · ${widget.equipmentCode}'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildServerPicker(theme),
              const Divider(height: 20),
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
            onPressed: _loading || _working ? null : _refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Ανανέωση'),
          ),
          FilledButton.icon(
            onPressed: _selectedSessionId == null || _working || _loading
                ? null
                : _disconnect,
            icon: const Icon(Icons.cast_connected_outlined, size: 18),
            label: const Text('Αποσύνδεση οθόνης'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: _selectedSessionId == null || _working || _loading
                ? null
                : _logoff,
            icon: const Icon(Icons.logout, size: 18),
            label: Text(_working ? 'Γίνεται…' : 'Τερματισμός'),
          ),
        ],
      ),
    );
  }

  Widget _buildServerPicker(ThemeData theme) {
    final choice = _choice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Διακομιστής'),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _server?.id,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  for (final s in _servers)
                    DropdownMenuItem(value: s.id, child: Text(s.displayLabel)),
                ],
                onChanged: _loading || _working
                    ? null
                    : (id) {
                        if (id == null) return;
                        setState(() {
                          _server = _servers.firstWhere((s) => s.id == id);
                        });
                        _refresh();
                      },
              ),
            ),
          ],
        ),
        if (choice != null) ...[
          const SizedBox(height: 6),
          Text(
            choice.explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Ερώτηση διακομιστή…'),
            ],
          ),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 10),
            Expanded(child: SelectableText(error)),
          ],
        ),
      );
    }

    final plan = _plan;
    if (plan == null || plan.candidates.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('Ο διακομιστής δεν έχει καμία ανοιχτή συνεδρία χρήστη.'),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan.needsExplicitChoice)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Ο σταθμός $_stationName έχει ${plan.matchCount} συνεδρίες — '
              'διάλεξε ποια θα κλείσει.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: plan.candidates.length,
            itemBuilder: (ctx, i) {
              final c = plan.candidates[i];
              return _SessionTile(
                candidate: c,
                selected: c.session.sessionId == _selectedSessionId,
                onTap: _working
                    ? null
                    : () => setState(
                        () => _selectedSessionId = c.session.sessionId,
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final LogoffCandidate candidate;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = candidate.session;
    final active = s.state == ServerSessionState.active;

    final station = s.stationName.trim().isEmpty
        ? 'σταθμός άγνωστος'
        : 'από ${s.stationName}';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                s.username,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                candidate.matchesEquipment
                    ? '$station — αυτός ο εξοπλισμός'
                    : station,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: candidate.matchesEquipment
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: candidate.matchesEquipment
                      ? FontWeight.w600
                      : null,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${s.state.label} · συνεδρία ${s.sessionId}'
          '${s.winStationName.isEmpty ? '' : ' · ${s.winStationName}'}',
        ),
        trailing: candidate.isAdminAccount
            ? Tooltip(
                message:
                    'Ο λογαριασμός διαχειριστή που χρησιμοποιεί η εφαρμογή',
                child: Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
              )
            : Icon(
                active ? Icons.circle : Icons.circle_outlined,
                size: 12,
                color: active
                    ? theme.colorScheme.error
                    : theme.colorScheme.tertiary,
              ),
      ),
    );
  }
}
