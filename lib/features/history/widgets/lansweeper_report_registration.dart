part of 'lansweeper_report_dialog.dart';

mixin LansweeperReportRegistrationMixin on LansweeperReportDialogStateHost {
  Future<void> _submitSelected(
    _ReportCallItem primary,
    List<_ReportCallItem> selected, {
    required bool resubmit,
  }) async {
    final item = primary;
    final callId = item.call.id;
    if (callId == null) return;
    if (_titleController.text.trim().isEmpty) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(content: Text('Ο τίτλος είναι υποχρεωτικός.')),
      );
      return;
    }

    if (_lansweeperAgentUsernameController.text.trim().isEmpty) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε τον πράκτορα API (username) στις ρυθμίσεις Lansweeper.',
          ),
        ),
      );
      return;
    }

    final apiUrl = ref.read(lansweeperApiUrlProvider);
    if (!LansweeperUrlRules.isApiEndpointUrl(apiUrl)) {
      if (!mounted) return;
      _showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε έγκυρο URL API (…/api.aspx) στις ρυθμίσεις Lansweeper για καταχώρηση.',
          ),
        ),
      );
      return;
    }

    if (resubmit &&
        (item.call.lansweeperMainTicketId ?? '').trim().isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Επαναϋποβολή'),
          content: const Text(
            'Η κλήση έχει ήδη κύριο Ticket ID. Θέλεις να γίνει νέα καταχώρηση;',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Συνέχεια'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final notifier = ref.read(lansweeperSyncProvider.notifier);
    final durationSeconds = selected.fold<int>(
      0,
      (sum, item) => sum + item.durationSeconds,
    );
    final input = LansweeperSubmitInput(
      title: _titleController.text,
      notes: _notesController.text,
      solution: _solutionController.text,
      agentUsername: _lansweeperAgentUsernameController.text,
      durationSeconds: durationSeconds,
    );
    final companionCallIds = selected
        .map((entry) => entry.call.id)
        .whereType<int>()
        .where((id) => id != callId)
        .toList();
    final result = resubmit
        ? await notifier.resubmitCall(
            callId: callId,
            input: input,
            companionCallIds: companionCallIds,
          )
        : await notifier.submitCall(
            callId: callId,
            input: input,
            companionCallIds: companionCallIds,
          );
    if (!mounted) return;
    if (result.success) {
      final ticketId = (result.ticketId ?? '').trim();
      final totalMarked = 1 + companionCallIds.length;
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            totalMarked == 1
                ? 'Καταχώρηση επιτυχής. Ticket: ${ticketId.isEmpty ? '-' : ticketId}'
                : ticketId.isEmpty
                ? '$totalMarked κλήσεις επισημάνθηκαν ως καταχωρημένες.'
                : '$totalMarked κλήσεις επισημάνθηκαν ως καταχωρημένες (ticket #$ticketId).',
          ),
        ),
      );
      if (!resubmit && ticketId.isNotEmpty) {
        final openTicketAfterSubmit =
            await readLansweeperOpenTicketAfterApiSubmitSetting();
        if (openTicketAfterSubmit) {
          await _openTicketViewInBrowser(ticketId);
        }
      }
      return;
    }

    final failureMessage = 'Αποτυχία καταχώρησης: ${result.message}';
    _showDialogSnackBar(
      SnackBar(
        content: Text(failureMessage),
        duration: const Duration(seconds: 8),
      ),
      copyText: failureMessage,
    );

    final reportText = (result.failureReport ?? result.message).trim();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αναφορά αποτυχίας καταχώρησης'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(child: SelectableText(reportText)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: reportText));
              if (!ctx.mounted) return;
              _showDialogSnackBar(
                const SnackBar(
                  content: Text('Η αναφορά αντιγράφηκε στο πρόχειρο.'),
                ),
              );
            },
            child: const Text('Αντιγραφή αναφοράς'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Κλείσιμο'),
          ),
        ],
      ),
    );
  }

  Future<bool> _markAsUnsentWithTicketPrompt(_ReportCallItem item) async {
    final callId = item.call.id;
    if (callId == null) return false;
    final storedTicket = (item.call.lansweeperMainTicketId ?? '').trim();
    final notifier = ref.read(lansweeperSyncProvider.notifier);
    if (storedTicket.isEmpty) {
      await notifier.setUnsent(callId);
      return true;
    }
    final choice = await showDialog<_UnsentTicketChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ακαταχώρητη κλήση'),
        content: Text(
          'Η κλήση έχει καταχωρηθεί με id: #$storedTicket στο Lansweeper.\n\n'
          'Τι θέλεις να γίνει με το ticket id;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsentTicketChoice.cancel),
            child: const Text('Άκυρο'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsentTicketChoice.clear),
            child: const Text('Μηδενισμός id'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsentTicketChoice.retain),
            child: const Text('Διατήρηση id'),
          ),
        ],
      ),
    );
    if (choice == null || choice == _UnsentTicketChoice.cancel) return false;
    await notifier.setUnsent(
      callId,
      retainTicketId: choice == _UnsentTicketChoice.retain,
    );
    return true;
  }

  Future<_DuplicateTicketAction> _promptDuplicateTicketWarning({
    required String ticketId,
    required int callId,
  }) async {
    final count = await ref
        .read(lansweeperSyncProvider.notifier)
        .countRegisteredCallsWithTicketId(ticketId, excludeCallId: callId);
    if (count <= 0) return _DuplicateTicketAction.proceed;
    if (!mounted) return _DuplicateTicketAction.cancel;
    final callsLabel = count == 1 ? 'άλλη κλήση' : 'άλλες κλήσεις';
    return await showDialog<_DuplicateTicketAction>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ίδιο Ticket ID'),
            content: Text(
              'Υπάρχουν $count $callsLabel καταχωρημένες με ticket #$ticketId.\n\n'
              'Συνήθως ένα ticket Lansweeper αντιστοιχεί σε ένα περιστατικό· '
              'πολλές κλήσεις με το ίδιο id επιτρέπονται (π.χ. ίδιος καλών / '
              'ομαδοποιημένες κλήσεις).',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(_DuplicateTicketAction.cancel),
                child: const Text('Άκυρο'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(_DuplicateTicketAction.changeId),
                child: const Text('Αλλαγή id'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(_DuplicateTicketAction.proceed),
                child: const Text('Πρόσθεση'),
              ),
            ],
          ),
        ) ??
        _DuplicateTicketAction.cancel;
  }

  Future<void> _applyRegistration({
    required _ReportCallItem item,
    String? comment,
    String title = 'Καταχώρηση κλήσης',
    String? subtitle,
  }) async {
    final callId = item.call.id;
    if (callId == null) return;
    var initialTicket = (item.call.lansweeperMainTicketId ?? '').trim();
    while (mounted) {
      final ticketId = await _promptOptionalTicketId(
        initialTicketId: initialTicket.isEmpty ? null : initialTicket,
        title: title,
        subtitle: subtitle,
      );
      if (ticketId == null) return;
      if (ticketId.isNotEmpty) {
        final duplicateAction = await _promptDuplicateTicketWarning(
          ticketId: ticketId,
          callId: callId,
        );
        if (duplicateAction == _DuplicateTicketAction.cancel) return;
        if (duplicateAction == _DuplicateTicketAction.changeId) {
          final next = await _promptOptionalTicketId(
            initialTicketId: ticketId,
            title: 'Αλλαγή Ticket ID',
          );
          if (next == null) return;
          initialTicket = next;
          continue;
        }
      }
      await ref.read(lansweeperSyncProvider.notifier).markRegistered(
        callId: callId,
        ticketId: ticketId.isEmpty ? null : ticketId,
        comment: comment,
      );
      if (!mounted) return;
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            ticketId.isEmpty
                ? 'Η κλήση επισημάνθηκε ως καταχωρημένη.'
                : 'Η κλήση επισημάνθηκε ως καταχωρημένη (ticket #$ticketId).',
          ),
        ),
      );
      return;
    }
  }

  Future<String?> _promptOptionalTicketId({
    String? initialTicketId,
    String title = 'Ticket Lansweeper',
    String? subtitle,
  }) async {
    final prefilled = await _resolveSuggestedTicketId(initialTicketId);
    if (!mounted) return null;
    final ticketController = TextEditingController(text: prefilled);
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subtitle != null) ...[
                  Text(subtitle, style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: ticketController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ticket ID (προαιρετικό)',
                    hintText: 'π.χ. 17132',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Αποθήκευση'),
            ),
          ],
        ),
      );
      if (accepted != true) return null;
      return ticketController.text.trim();
    } finally {
      ticketController.dispose();
    }
  }

  Future<String> _resolveSuggestedTicketId(String? existingTicketId) async {
    final trimmed = (existingTicketId ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed;
    return await ref
            .read(lansweeperSyncProvider.notifier)
            .suggestedNextLansweeperTicketId() ??
        '';
  }

  Future<void> _manualMark(_ReportCallItem item) async {
    final callId = item.call.id;
    if (callId == null) return;
    final initialTicket = await _resolveSuggestedTicketId(
      item.call.lansweeperMainTicketId,
    );
    if (!mounted) return;
    final ticketController = TextEditingController(text: initialTicket);
    final commentController = TextEditingController();
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Χειροκίνητη Σήμανση'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ticketController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ticket ID (προαιρετικό)',
                    hintText: 'π.χ. 17132',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: commentController,
                  decoration: const InputDecoration(
                    labelText: 'Σχόλιο/Αιτιολογία (προαιρετικό)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Αποθήκευση'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      var ticketId = ticketController.text.trim();
      final comment = commentController.text;
      while (mounted) {
        if (ticketId.isNotEmpty) {
          final duplicateAction = await _promptDuplicateTicketWarning(
            ticketId: ticketId,
            callId: callId,
          );
          if (duplicateAction == _DuplicateTicketAction.cancel) return;
          if (duplicateAction == _DuplicateTicketAction.changeId) {
            final next = await _promptOptionalTicketId(
              initialTicketId: ticketId,
              title: 'Αλλαγή Ticket ID',
            );
            if (next == null) return;
            ticketId = next;
            continue;
          }
        }
        await ref.read(lansweeperSyncProvider.notifier).markRegistered(
          callId: callId,
          ticketId: ticketId.isEmpty ? null : ticketId,
          comment: comment,
        );
        if (!mounted) return;
        _showDialogSnackBar(
          SnackBar(
            content: Text(
              ticketId.isEmpty
                  ? 'Η κλήση επισημάνθηκε ως καταχωρημένη.'
                  : 'Η κλήση επισημάνθηκε ως καταχωρημένη (ticket #$ticketId).',
            ),
          ),
        );
        return;
      }
    } finally {
      ticketController.dispose();
      commentController.dispose();
    }
  }

  Future<void> _toggleRegistrationFromBadge(_ReportCallItem item) async {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    if (state == LansweeperSyncState.sent) {
      final changed = await _markAsUnsentWithTicketPrompt(item);
      if (!changed || !mounted) return;
      _showDialogSnackBar(
        const SnackBar(content: Text('Η κλήση σημειώθηκε ως ακαταχώρητη.')),
      );
      return;
    }
    await _applyRegistration(
      item: item,
      title: 'Καταχώρηση κλήσης',
      subtitle: 'Ο αριθμός ticket Lansweeper είναι προαιρετικός (π.χ. 17132).',
    );
  }

  Future<void> _applyBulkRegistration(List<_ReportCallItem> items) async {
    final validItems = items.where((item) => item.call.id != null).toList();
    if (validItems.isEmpty) return;

    final count = validItems.length;
    var initialTicket = count == 1
        ? (validItems.first.call.lansweeperMainTicketId ?? '').trim()
        : '';
    initialTicket = await _resolveSuggestedTicketId(
      initialTicket.isEmpty ? null : initialTicket,
    );
    if (!mounted) return;

    while (mounted) {
      final ticketId = await _promptOptionalTicketId(
        initialTicketId: initialTicket.isEmpty ? null : initialTicket,
        title: count == 1 ? 'Καταχώρηση κλήσης' : 'Καταχώρηση $count κλήσεων',
        subtitle: count == 1
            ? 'Ο αριθμός ticket Lansweeper είναι προαιρετικός (π.χ. 17132).'
            : 'Ο αριθμός ticket Lansweeper είναι προαιρετικός και θα εφαρμοστεί σε όλες τις επιλεγμένες κλήσεις.',
      );
      if (ticketId == null) return;
      if (ticketId.isNotEmpty) {
        final duplicateAction = await _promptDuplicateTicketWarning(
          ticketId: ticketId,
          callId: validItems.first.call.id!,
        );
        if (duplicateAction == _DuplicateTicketAction.cancel) return;
        if (duplicateAction == _DuplicateTicketAction.changeId) {
          final next = await _promptOptionalTicketId(
            initialTicketId: ticketId,
            title: 'Αλλαγή Ticket ID',
          );
          if (next == null) return;
          initialTicket = next;
          continue;
        }
      }

      final notifier = ref.read(lansweeperSyncProvider.notifier);
      for (final item in validItems) {
        await notifier.markRegistered(
          callId: item.call.id!,
          ticketId: ticketId.isEmpty ? null : ticketId,
        );
      }
      if (!mounted) return;
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? ticketId.isEmpty
                      ? 'Η κλήση επισημάνθηκε ως καταχωρημένη.'
                      : 'Η κλήση επισημάνθηκε ως καταχωρημένη (ticket #$ticketId).'
                : ticketId.isEmpty
                ? '$count κλήσεις επισημάνθηκαν ως καταχωρημένες.'
                : '$count κλήσεις επισημάνθηκαν ως καταχωρημένες (ticket #$ticketId).',
          ),
        ),
      );
      return;
    }
  }

  Future<void> _setStateForAllSelected(
    List<_ReportCallItem> selected,
    String nextState,
  ) async {
    final toUpdate = selected
        .where((item) => _normalizedLansweeperState(item) != nextState)
        .toList();
    if (toUpdate.isEmpty) return;

    if (nextState == LansweeperSyncState.excluded) {
      final notifier = ref.read(lansweeperSyncProvider.notifier);
      var count = 0;
      for (final item in toUpdate) {
        final callId = item.call.id;
        if (callId == null) continue;
        await notifier.setExcluded(callId);
        count++;
      }
      if (!mounted || count == 0) return;
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Η κλήση επισημάνθηκε ως εξαιρεμένη.'
                : '$count κλήσεις επισημάνθηκαν ως εξαιρεμένες.',
          ),
        ),
      );
      return;
    }

    if (nextState == LansweeperSyncState.unsent) {
      var count = 0;
      for (final item in toUpdate) {
        final changed = await _markAsUnsentWithTicketPrompt(item);
        if (!changed) break;
        count++;
      }
      if (!mounted || count == 0) return;
      _showDialogSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Η κλήση σημειώθηκε ως ακαταχώρητη.'
                : '$count κλήσεις σημειώθηκαν ως ακαταχώρητες.',
          ),
        ),
      );
      return;
    }

    if (nextState == LansweeperSyncState.sent) {
      await _applyBulkRegistration(toUpdate);
    }
  }
}
