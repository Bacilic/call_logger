part of 'lansweeper_report_dialog.dart';

mixin LansweeperReportRegistrationMixin on LansweeperReportDialogStateHost {
  Future<void> _submitSelected(
    ReportCallItem primary,
    List<ReportCallItem> selected, {
    required bool resubmit,
  }) async {
    final item = primary;
    final callId = item.call.id;
    if (callId == null) return;
    if (_titleController.text.trim().isEmpty) {
      if (!mounted) return;
      showDialogSnackBar(
        const SnackBar(content: Text('Ο τίτλος είναι υποχρεωτικός.')),
      );
      return;
    }

    if (_lansweeperAgentUsernameController.text.trim().isEmpty) {
      if (!mounted) return;
      showDialogSnackBar(
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
      showDialogSnackBar(
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
      final confirmed = await showLansweeperResubmitConfirmDialog(context);
      if (confirmed != true) return;
    }

    final notifier = ref.read(lansweeperSyncProvider.notifier);
    final durationSeconds = selected.fold<int>(
      0,
      (sum, item) => sum + item.durationSeconds,
    );
    final ticketConfig = ref.read(lansweeperTicketSubmitConfigProvider);
    final resolvedCustomFields = <String, String>{
      for (final field in ticketConfig.customFields)
        field.id: (_customFieldValues[field.id] ?? field.defaultValue),
    };
    final input = LansweeperSubmitInput(
      title: _titleController.text,
      notes: _notesController.text,
      solution: _solutionController.text,
      agentUsername: _lansweeperAgentUsernameController.text,
      durationSeconds: durationSeconds,
      config: ticketConfig,
      customFieldValues: resolvedCustomFields,
      targetTicketState:
          _selectedTicketState ?? ticketConfig.defaultTicketState,
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
      await _persistTicketSubmitFormPrefs();
      if (!mounted) return;
      final ticketId = (result.ticketId ?? '').trim();
      final totalMarked = 1 + companionCallIds.length;
      final baseMessage = totalMarked == 1
          ? 'Καταχώρηση επιτυχής. Ticket: ${ticketId.isEmpty ? '-' : ticketId}'
          : ticketId.isEmpty
          ? '$totalMarked κλήσεις επισημάνθηκαν ως καταχωρημένες.'
          : '$totalMarked κλήσεις επισημάνθηκαν ως καταχωρημένες (ticket #$ticketId).';
      final warningsText = result.warnings.isEmpty
          ? ''
          : '\n${result.warnings.join('\n')}';
      showDialogSnackBar(
        SnackBar(content: Text('$baseMessage$warningsText')),
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

    await _persistTicketSubmitFormPrefs();
    if (!mounted) return;

    final failedStep = (result.failedStep ?? '').trim();
    final failureMessage = failedStep.isEmpty
        ? 'Αποτυχία καταχώρησης: ${result.message}'
        : 'Αποτυχία καταχώρησης ($failedStep): ${result.message}';
    showDialogSnackBar(
      SnackBar(
        content: Text(failureMessage),
        duration: const Duration(seconds: 8),
      ),
      copyText: failureMessage,
    );

    final reportBase = (result.failureReport ?? result.message).trim();
    final reportText = failedStep.isEmpty
        ? reportBase
        : 'failedStep: $failedStep\n$reportBase';
    await showLansweeperFailureReportDialog(
      context,
      reportText: reportText,
      onCopied: () => showDialogSnackBar(
        const SnackBar(
          content: Text('Η αναφορά αντιγράφηκε στο πρόχειρο.'),
        ),
      ),
    );
  }

  Future<bool> _markAsUnsentWithTicketPrompt(ReportCallItem item) async {
    final callId = item.call.id;
    if (callId == null) return false;
    final storedTicket = (item.call.lansweeperMainTicketId ?? '').trim();
    final notifier = ref.read(lansweeperSyncProvider.notifier);
    if (storedTicket.isEmpty) {
      await notifier.setUnsent(callId);
      return true;
    }
    final choice = await showLansweeperUnsentTicketChoiceDialog(
      context,
      storedTicket: storedTicket,
    );
    if (choice == null || choice == UnsentTicketChoice.cancel) return false;
    await notifier.setUnsent(
      callId,
      retainTicketId: choice == UnsentTicketChoice.retain,
    );
    return true;
  }

  Future<DuplicateTicketAction> _promptDuplicateTicketWarning({
    required String ticketId,
    required int callId,
  }) async {
    final count = await ref
        .read(lansweeperSyncProvider.notifier)
        .countRegisteredCallsWithTicketId(ticketId, excludeCallId: callId);
    if (count <= 0) return DuplicateTicketAction.proceed;
    if (!mounted) return DuplicateTicketAction.cancel;
    return showLansweeperDuplicateTicketDialog(
      context,
      count: count,
      ticketId: ticketId,
    );
  }

  Future<void> _applyRegistration({
    required ReportCallItem item,
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
        if (duplicateAction == DuplicateTicketAction.cancel) return;
        if (duplicateAction == DuplicateTicketAction.changeId) {
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
      showDialogSnackBar(
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
    return showLansweeperOptionalTicketIdDialog(
      context,
      prefilled: prefilled,
      title: title,
      subtitle: subtitle,
    );
  }

  Future<String> _resolveSuggestedTicketId(String? existingTicketId) async {
    final trimmed = (existingTicketId ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed;
    return await ref
            .read(lansweeperSyncProvider.notifier)
            .suggestedNextLansweeperTicketId() ??
        '';
  }

  Future<void> _manualMark(ReportCallItem item) async {
    final callId = item.call.id;
    if (callId == null) return;
    final initialTicket = await _resolveSuggestedTicketId(
      item.call.lansweeperMainTicketId,
    );
    if (!mounted) return;
    final input = await showLansweeperManualMarkDialog(
      context,
      initialTicket: initialTicket,
    );
    if (input == null) return;
    var ticketId = input.ticketId;
    final comment = input.comment;
    while (mounted) {
      if (ticketId.isNotEmpty) {
        final duplicateAction = await _promptDuplicateTicketWarning(
          ticketId: ticketId,
          callId: callId,
        );
        if (duplicateAction == DuplicateTicketAction.cancel) return;
        if (duplicateAction == DuplicateTicketAction.changeId) {
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
      showDialogSnackBar(
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

  Future<void> _toggleRegistrationFromBadge(ReportCallItem item) async {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    if (state == LansweeperSyncState.sent) {
      final changed = await _markAsUnsentWithTicketPrompt(item);
      if (!changed || !mounted) return;
      showDialogSnackBar(
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

  Future<void> _applyBulkRegistration(List<ReportCallItem> items) async {
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
        if (duplicateAction == DuplicateTicketAction.cancel) return;
        if (duplicateAction == DuplicateTicketAction.changeId) {
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
      showDialogSnackBar(
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
    List<ReportCallItem> selected,
    String nextState,
  ) async {
    final toUpdate = selected
        .where(
          (item) =>
              LansweeperReportItemMapper.normalizedLansweeperState(item) !=
              nextState,
        )
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
      showDialogSnackBar(
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
      showDialogSnackBar(
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
