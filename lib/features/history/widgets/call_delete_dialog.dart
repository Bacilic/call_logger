import '../../../core/widgets/dialog_snackbar_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/history_call_actions_provider.dart';

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

class _CallDeleteDialogState extends ConsumerState<_CallDeleteDialog>
    with DialogSnackbarHost {
  bool _loading = true;
  bool _busy = false;
  int _linkedTasks = 0;
  bool _hardDelete = false;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final count = await ref
        .read(historyCallActionsServiceProvider)
        .countLinkedTasks(widget.callId);
    if (!mounted) return;
    setState(() {
      _linkedTasks = count;
      _loading = false;
    });
  }

  Future<void> _delete({required String taskAction}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_hardDelete) {
        await ref
            .read(historyCallActionsServiceProvider)
            .hardDeleteCall(
              widget.callId,
              callerId: widget.callerId,
              equipmentCode: widget.equipmentCode,
            );
      } else {
        await ref
            .read(historyCallActionsServiceProvider)
            .deleteCall(
              widget.callId,
              taskAction: taskAction,
              callerId: widget.callerId,
              equipmentCode: widget.equipmentCode,
            );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hardDelete
                ? 'Η κλήση διαγράφηκε οριστικά.'
                : 'Η κλήση διαγράφηκε επιτυχώς.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showDialogSnackBar(
        SnackBar(content: Text('Αποτυχία διαγραφής: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: Center(
        child: AlertDialog(
      title: const Text('Διαγραφή κλήσης'),
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_linkedTasks > 0)
                  Text(
                    'Βρέθηκαν $_linkedTasks συνδεδεμένες εκκρεμότητες για την κλήση.',
                  )
                else
                  const Text('Επιβεβαιώστε τη διαγραφή της κλήσης.'),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Οριστική διαγραφή (hard delete)'),
                  subtitle: const Text('Χωρίς δυνατότητα επαναφοράς.'),
                  value: _hardDelete,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _hardDelete = v),
                ),
              ],
            ),
      actions: _loading
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Κλείσιμο'),
              ),
            ]
          : [
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Ακύρωση διαγραφής'),
              ),
              if (_linkedTasks > 0) ...[
                FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () => _delete(taskAction: 'nullify'),
                  child: const Text('Διαγραφή μόνο κλήσης (αποσύνδεση tasks)'),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _delete(taskAction: 'cascade'),
                  child: const Text(
                    'Διαγραφή κλήσης και συνδεδεμένων εκκρεμοτήτων',
                  ),
                ),
              ] else
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _delete(taskAction: 'nullify'),
                  child: const Text('Διαγραφή κλήσης'),
                ),
            ],
        ),
      ),
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

class _CallBulkDeleteDialogState extends ConsumerState<_CallBulkDeleteDialog>
    with DialogSnackbarHost {
  bool _loading = true;
  bool _busy = false;
  int _linkedTasksCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final count = await ref
        .read(historyCallActionsServiceProvider)
        .countLinkedTasksForCalls(widget.callIds);
    if (!mounted) return;
    setState(() {
      _linkedTasksCount = count;
      _loading = false;
    });
  }

  Future<void> _executeDelete(String? taskAction) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(historyCallActionsServiceProvider)
          .bulkSoftDelete(widget.callIds, taskAction: taskAction);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Διαγράφηκαν ${widget.callIds.length} κλήσεις.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showDialogSnackBar(
        SnackBar(content: Text('Αποτυχία μαζικής διαγραφής: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: Center(
        child: AlertDialog(
      title: const Text('Μαζική διαγραφή κλήσεων'),
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : Text(
              _linkedTasksCount > 0
                  ? 'Οι ${widget.callIds.length} επιλεγμένες κλήσεις έχουν συνολικά $_linkedTasksCount συνδεδεμένες εκκρεμότητες.'
                  : 'Να διαγραφούν οι ${widget.callIds.length} επιλεγμένες κλήσεις;',
            ),
      actions: _loading
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Κλείσιμο'),
              ),
            ]
          : [
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Ακύρωση'),
              ),
              if (_linkedTasksCount > 0) ...[
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _executeDelete('nullify'),
                  child: const Text('Διαγραφή μόνο κλήσεων (αποσύνδεση tasks)'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _executeDelete('cascade'),
                  child: const Text(
                    'Διαγραφή κλήσεων + συνδεδεμένων εκκρεμοτήτων',
                  ),
                ),
              ] else
                FilledButton(
                  onPressed: _busy ? null : () => _executeDelete('nullify'),
                  child: const Text('Μαζική διαγραφή'),
                ),
            ],
        ),
      ),
    );
  }
}
