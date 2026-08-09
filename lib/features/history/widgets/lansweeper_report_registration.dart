import 'package:flutter/material.dart';

import '../models/lansweeper_sync_state.dart';
import '../providers/lansweeper_settings_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import '../providers/lansweeper_ticket_submit_config_provider.dart';
import 'lansweeper/lansweeper_ai_presenter.dart';
import 'lansweeper/lansweeper_registration_dialogs.dart';
import 'lansweeper/lansweeper_report_item_mapper.dart';
import 'lansweeper/lansweeper_url_rules.dart';
import 'lansweeper_report_dialog.dart';

/// Καταχώρηση κλήσεων στο Lansweeper: υποβολή API, χειροκίνητη σήμανση,
/// μαζικές αλλαγές κατάστασης.
///
/// Συνεργάτης του [LansweeperReportDialogState] (Σύνθεση).
class LansweeperReportRegistration {
  LansweeperReportRegistration(this.host);

  final LansweeperReportDialogState host;

  Future<void> submitSelected(
    ReportCallItem primary,
    List<ReportCallItem> selected, {
    required bool resubmit,
  }) async {
    final item = primary;
    final callId = item.call.id;
    if (callId == null) return;
    if (host.titleController.text.trim().isEmpty) {
      if (!host.mounted) return;
      host.showDialogSnackBar(
        const SnackBar(content: Text('Ο τίτλος είναι υποχρεωτικός.')),
      );
      return;
    }

    if (host.lansweeperAgentUsernameController.text.trim().isEmpty) {
      if (!host.mounted) return;
      host.showDialogSnackBar(
        const SnackBar(
          content: Text(
            'Ορίστε τον πράκτορα API (username) στις ρυθμίσεις Lansweeper.',
          ),
        ),
      );
      return;
    }

    final apiUrl = host.ref.read(lansweeperApiUrlProvider);
    if (!LansweeperUrlRules.isApiEndpointUrl(apiUrl)) {
      if (!host.mounted) return;
      host.showDialogSnackBar(
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
      final confirmed = await showLansweeperResubmitConfirmDialog(host.context);
      if (confirmed != true) return;
    }

    final notifier = host.ref.read(lansweeperSyncProvider.notifier);
    final durationSeconds = selected.fold<int>(
      0,
      (sum, item) => sum + item.durationSeconds,
    );
    final ticketConfig = host.ref.read(lansweeperTicketSubmitConfigProvider);
    final resolvedCustomFields = <String, String>{
      for (final field in ticketConfig.customFields)
        field.id: (host.customFieldValues[field.id] ?? field.defaultValue),
    };
    final input = LansweeperSubmitInput(
      title: host.titleController.text,
      notes: host.notesController.text,
      solution: host.solutionController.text,
      refinedSource: LansweeperAiPresenter.refinedSource(
        aiProblem: host.aiSuggestedNotes,
        aiSolution: host.aiSuggestedSolution,
        problem: host.notesController.text,
        solution: host.solutionController.text,
      ),
      agentUsername: host.lansweeperAgentUsernameController.text,
      durationSeconds: durationSeconds,
      config: ticketConfig,
      customFieldValues: resolvedCustomFields,
      targetTicketState:
          host.selectedTicketState ?? ticketConfig.defaultTicketState,
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
    if (!host.mounted) return;
    if (result.success) {
      await host.persistTicketSubmitFormPrefs();
      if (!host.mounted) return;
      // Οι κλήσεις πέρασαν στις Καταχωρημένες — παραμένοντας επιλεγμένες εκεί
      // δεν εξυπηρετούν τίποτα και μπερδεύουν την επόμενη ενέργεια.
      for (final entry in selected) {
        host.selectedKeys.remove(entry.key);
      }
      host.notifyReportChanged();
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
      host.showDialogSnackBar(
        SnackBar(content: Text('$baseMessage$warningsText')),
      );
      if (!resubmit && ticketId.isNotEmpty) {
        final openTicketAfterSubmit =
            await readLansweeperOpenTicketAfterApiSubmitSetting();
        if (openTicketAfterSubmit) {
          await host.browserFlow.openTicketViewInBrowser(ticketId);
        }
      }
      return;
    }

    await host.persistTicketSubmitFormPrefs();
    if (!host.mounted) return;

    final failedStep = (result.failedStep ?? '').trim();
    final failureMessage = failedStep.isEmpty
        ? 'Αποτυχία καταχώρησης: ${result.message}'
        : 'Αποτυχία καταχώρησης ($failedStep): ${result.message}';
    host.showDialogSnackBar(
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
      host.context,
      reportText: reportText,
      onCopied: () => host.showDialogSnackBar(
        const SnackBar(content: Text('Η αναφορά αντιγράφηκε στο πρόχειρο.')),
      ),
    );
  }

  Future<bool> _markAsUnsentWithTicketPrompt(ReportCallItem item) async {
    final callId = item.call.id;
    if (callId == null) return false;
    final storedTicket = (item.call.lansweeperMainTicketId ?? '').trim();
    final notifier = host.ref.read(lansweeperSyncProvider.notifier);
    if (storedTicket.isEmpty) {
      await notifier.setUnsent(callId);
      return true;
    }
    final choice = await showLansweeperUnsentTicketChoiceDialog(
      host.context,
      storedTicket: storedTicket,
      ticketViewUrlTemplate: host.ref.read(lansweeperTicketViewUrlProvider),
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
    final count = await host.ref
        .read(lansweeperSyncProvider.notifier)
        .countRegisteredCallsWithTicketId(ticketId, excludeCallId: callId);
    if (count <= 0) return DuplicateTicketAction.proceed;
    if (!host.mounted) return DuplicateTicketAction.cancel;
    return showLansweeperDuplicateTicketDialog(
      host.context,
      count: count,
      ticketId: ticketId,
      ticketViewUrlTemplate: host.ref.read(lansweeperTicketViewUrlProvider),
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
    while (host.mounted) {
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
      await host.ref
          .read(lansweeperSyncProvider.notifier)
          .markRegistered(
            callId: callId,
            ticketId: ticketId.isEmpty ? null : ticketId,
            comment: comment,
          );
      if (!host.mounted) return;
      host.showDialogSnackBar(
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
    if (!host.mounted) return null;
    return showLansweeperOptionalTicketIdDialog(
      host.context,
      prefilled: prefilled,
      title: title,
      subtitle: subtitle,
    );
  }

  Future<String> _resolveSuggestedTicketId(String? existingTicketId) async {
    final trimmed = (existingTicketId ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed;
    return await host.ref
            .read(lansweeperSyncProvider.notifier)
            .suggestedNextLansweeperTicketId() ??
        '';
  }

  Future<void> manualMark(ReportCallItem item) async {
    final callId = item.call.id;
    if (callId == null) return;
    final initialTicket = await _resolveSuggestedTicketId(
      item.call.lansweeperMainTicketId,
    );
    if (!host.mounted) return;
    final input = await showLansweeperManualMarkDialog(
      host.context,
      initialTicket: initialTicket,
    );
    if (input == null) return;
    var ticketId = input.ticketId;
    final comment = input.comment;
    while (host.mounted) {
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
      await host.ref
          .read(lansweeperSyncProvider.notifier)
          .markRegistered(
            callId: callId,
            ticketId: ticketId.isEmpty ? null : ticketId,
            comment: comment,
          );
      if (!host.mounted) return;
      host.showDialogSnackBar(
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

  Future<void> toggleRegistrationFromBadge(ReportCallItem item) async {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    if (state == LansweeperSyncState.sent) {
      final changed = await _markAsUnsentWithTicketPrompt(item);
      if (!changed || !host.mounted) return;
      host.showDialogSnackBar(
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
    if (!host.mounted) return;

    while (host.mounted) {
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

      final notifier = host.ref.read(lansweeperSyncProvider.notifier);
      for (final item in validItems) {
        await notifier.markRegistered(
          callId: item.call.id!,
          ticketId: ticketId.isEmpty ? null : ticketId,
        );
      }
      if (!host.mounted) return;
      host.showDialogSnackBar(
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

  Future<void> setStateForAllSelected(
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
      final notifier = host.ref.read(lansweeperSyncProvider.notifier);
      var count = 0;
      for (final item in toUpdate) {
        final callId = item.call.id;
        if (callId == null) continue;
        await notifier.setExcluded(callId);
        count++;
      }
      if (!host.mounted || count == 0) return;
      host.showDialogSnackBar(
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
      if (!host.mounted || count == 0) return;
      host.showDialogSnackBar(
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
