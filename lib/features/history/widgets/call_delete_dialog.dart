import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/call_deletion_impact.dart';
import '../../../core/providers/pending_deferred_actions_provider.dart';
import '../../../core/widgets/draggable_dialog_shell.dart';
import '../providers/history_call_actions_provider.dart';
import '../services/call_deletion_messages.dart';
import 'call_deletion_dialog_parts.dart';
import 'deferred_deletion_snackbar.dart';

/// Πλάτος και των δύο διαλόγων: η λίστα συνδέσεων θέλει σταθερή στήλη ώρας.
const double _kDialogWidth = 520;

Future<void> showCallDeleteDialog(
  BuildContext context, {
  required int callId,
  int? callerId,
  String? equipmentCode,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CallDeleteDialog(
      callId: callId,
      callerId: callerId,
      equipmentCode: equipmentCode,
    ),
  );
}

Future<void> showCallBulkDeleteDialog(
  BuildContext context, {
  required List<int> callIds,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CallBulkDeleteDialog(callIds: callIds),
  );
}

class _CallDeleteDialog extends ConsumerStatefulWidget {
  const _CallDeleteDialog({
    required this.callId,
    this.callerId,
    this.equipmentCode,
  });

  final int callId;
  final int? callerId;
  final String? equipmentCode;

  @override
  ConsumerState<_CallDeleteDialog> createState() => _CallDeleteDialogState();
}

class _CallDeleteDialogState extends ConsumerState<_CallDeleteDialog> {
  bool _loading = true;
  bool _busy = false;
  CallDeletionImpact _impact = CallDeletionImpact.empty;
  bool _hardDelete = false;

  @override
  void initState() {
    super.initState();
    _loadImpact();
  }

  Future<void> _loadImpact() async {
    final impact = await ref
        .read(historyCallActionsServiceProvider)
        .callDeletionImpact([widget.callId]);
    if (!mounted) return;
    setState(() {
      _impact = impact;
      _loading = false;
    });
  }

  void _delete({required String taskAction}) {
    if (_busy) return;
    setState(() => _busy = true);
    // Ο διακόπτης λέει ΠΟΣΟ βαθιά σβήνει η διαγραφή· τι γίνονται οι
    // εκκρεμότητες το λέει πάντα το κουμπί που πάτησε ο χρήστης.
    // Όλα διαβάζονται πριν το κλείσιμο: το ref του διαλόγου πεθαίνει με το pop,
    // ενώ η εκτέλεση θα τρέξει μετά το παράθυρο αναίρεσης.
    final actions = ref.read(historyCallActionsServiceProvider);
    final deferredActions = ref.read(pendingDeferredActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final hard = _hardDelete;
    final callId = widget.callId;
    final callerId = widget.callerId;
    final equipmentCode = widget.equipmentCode;
    Navigator.of(context).pop();

    scheduleDeferredDeletionWithUndo(
      messenger: messenger,
      deferredActions: deferredActions,
      label: 'Διαγραφή κλήσης',
      countdownMessage: (s) => hard
          ? 'Η κλήση θα διαγραφεί οριστικά σε $s″.'
          : 'Η κλήση θα διαγραφεί σε $s″.',
      completedMessage: hard
          ? 'Η κλήση διαγράφηκε οριστικά.'
          : 'Η κλήση διαγράφηκε.',
      failureMessage: 'Η διαγραφή απέτυχε — η κλήση παραμένει.',
      execute: () => actions.deleteCall(
        callId,
        taskAction: taskAction,
        hard: hard,
        callerId: callerId,
        equipmentCode: equipmentCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableDialogShell(
      title: const Text('Διαγραφή κλήσης'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: _loading
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : SizedBox(width: _kDialogWidth, child: _buildBody(context)),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(_loading ? 'Κλείσιμο' : 'Ακύρωση διαγραφής'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final hardDeleteWarning = callHardDeleteLossWarning(_impact);
    final lansweeperNote = callLansweeperUnaffectedNote(
      _impact,
      hardDelete: _hardDelete,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(callDeletionHeadline(_impact)),
        if (_impact.hasConnections) ...[
          const SizedBox(height: 8),
          CallConnectionsCard(impact: _impact),
        ],
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Οριστική διαγραφή (hard delete)'),
          subtitle: const Text('Χωρίς δυνατότητα επαναφοράς.'),
          value: _hardDelete,
          onChanged: _busy ? null : (v) => setState(() => _hardDelete = v),
        ),
        if (_hardDelete && hardDeleteWarning != null) ...[
          const SizedBox(height: 4),
          Text(
            hardDeleteWarning,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        if (_impact.hasLinkedTasks) ...[
          CallDeletionChoiceButton(
            label: callKeepTasksButtonLabel(callCount: 1),
            hint: callKeepTasksButtonHint(_impact),
            onPressed: _busy ? null : () => _delete(taskAction: 'nullify'),
          ),
          const SizedBox(height: 8),
          CallDeletionChoiceButton(
            label: callCascadeButtonLabel(callCount: 1),
            hint: callCascadeButtonHint(_impact),
            emphasized: true,
            onPressed: _busy ? null : () => _delete(taskAction: 'cascade'),
          ),
        ] else
          FilledButton(
            onPressed: _busy ? null : () => _delete(taskAction: 'nullify'),
            child: const Text('Διαγραφή κλήσης'),
          ),
        if (lansweeperNote != null) ...[
          const SizedBox(height: 8),
          Text(
            lansweeperNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CallBulkDeleteDialog extends ConsumerStatefulWidget {
  const _CallBulkDeleteDialog({required this.callIds});

  final List<int> callIds;

  @override
  ConsumerState<_CallBulkDeleteDialog> createState() =>
      _CallBulkDeleteDialogState();
}

class _CallBulkDeleteDialogState extends ConsumerState<_CallBulkDeleteDialog> {
  bool _loading = true;
  bool _busy = false;
  CallDeletionImpact _impact = CallDeletionImpact.empty;
  bool _hardDelete = false;

  @override
  void initState() {
    super.initState();
    _loadImpact();
  }

  Future<void> _loadImpact() async {
    final impact = await ref
        .read(historyCallActionsServiceProvider)
        .callDeletionImpact(widget.callIds);
    if (!mounted) return;
    setState(() {
      _impact = impact;
      _loading = false;
    });
  }

  void _executeDelete(String? taskAction) {
    if (_busy) return;
    setState(() => _busy = true);
    // Όλα διαβάζονται πριν το κλείσιμο: το ref του διαλόγου πεθαίνει με το pop,
    // ενώ η εκτέλεση θα τρέξει μετά το παράθυρο αναίρεσης.
    final actions = ref.read(historyCallActionsServiceProvider);
    final deferredActions = ref.read(pendingDeferredActionsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final hard = _hardDelete;
    final callIds = List<int>.of(widget.callIds);
    Navigator.of(context).pop();

    final count = callIds.length;
    scheduleDeferredDeletionWithUndo(
      messenger: messenger,
      deferredActions: deferredActions,
      label: 'Μαζική διαγραφή $count κλήσεων',
      countdownMessage: (s) => count == 1
          ? (hard
                ? 'Η κλήση θα διαγραφεί οριστικά σε $s″.'
                : 'Η κλήση θα διαγραφεί σε $s″.')
          : (hard
                ? 'Οι $count κλήσεις θα διαγραφούν οριστικά σε $s″.'
                : 'Οι $count κλήσεις θα διαγραφούν σε $s″.'),
      completedMessage: count == 1
          ? (hard ? 'Η κλήση διαγράφηκε οριστικά.' : 'Η κλήση διαγράφηκε.')
          : (hard
                ? 'Διαγράφηκαν οριστικά $count κλήσεις.'
                : 'Διαγράφηκαν $count κλήσεις.'),
      failureMessage: 'Η μαζική διαγραφή απέτυχε — οι κλήσεις παραμένουν.',
      execute: () =>
          actions.bulkDelete(callIds, taskAction: taskAction, hard: hard),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableDialogShell(
      title: const Text('Μαζική διαγραφή κλήσεων'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: _loading
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : SizedBox(width: _kDialogWidth, child: _buildBody(context)),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(_loading ? 'Κλείσιμο' : 'Ακύρωση'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final callCount = widget.callIds.length;
    final hardDeleteWarning = callBulkHardDeleteLossWarning(_impact);
    final lansweeperNote = callLansweeperUnaffectedNote(
      _impact,
      hardDelete: _hardDelete,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(callBulkDeletionHeadline(_impact, callCount: callCount)),
        if (_impact.connectedCalls.isNotEmpty) ...[
          const SizedBox(height: 8),
          CallConnectionRowsList(impact: _impact),
        ],
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Οριστική διαγραφή (hard delete)'),
          subtitle: const Text('Χωρίς δυνατότητα επαναφοράς.'),
          value: _hardDelete,
          onChanged: _busy ? null : (v) => setState(() => _hardDelete = v),
        ),
        if (_hardDelete && hardDeleteWarning != null) ...[
          const SizedBox(height: 4),
          Text(
            hardDeleteWarning,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        if (_impact.hasLinkedTasks) ...[
          CallDeletionChoiceButton(
            label: callKeepTasksButtonLabel(callCount: callCount),
            hint: callKeepTasksButtonHint(_impact),
            onPressed: _busy ? null : () => _executeDelete('nullify'),
          ),
          const SizedBox(height: 8),
          CallDeletionChoiceButton(
            label: callCascadeButtonLabel(callCount: callCount),
            hint: callCascadeButtonHint(_impact),
            emphasized: true,
            onPressed: _busy ? null : () => _executeDelete('cascade'),
          ),
        ] else
          FilledButton(
            onPressed: _busy ? null : () => _executeDelete('nullify'),
            child: const Text('Μαζική διαγραφή'),
          ),
        if (lansweeperNote != null) ...[
          const SizedBox(height: 8),
          Text(
            lansweeperNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
