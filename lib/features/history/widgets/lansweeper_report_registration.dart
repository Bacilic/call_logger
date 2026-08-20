import 'package:flutter/material.dart';

import '../models/lansweeper_sync_state.dart';
import '../providers/lansweeper_settings_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import '../providers/lansweeper_ticket_submit_config_provider.dart';
import '../services/lansweeper_submission_warnings.dart';
import 'lansweeper/lansweeper_ai_presenter.dart';
import 'lansweeper/lansweeper_registration_dialogs.dart';
import 'lansweeper/lansweeper_registration_flow.dart';
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
      requesterUsername: host.selectedRequesterUsername,
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
      final message = lansweeperSubmitSnackBarText(
        baseMessage: baseMessage,
        warnings: result.warnings,
      );
      if (result.warnings.isEmpty) {
        host.showDialogSnackBar(SnackBar(content: Text(message)));
      } else {
        // Οι προειδοποιήσεις κρύβονταν κάτω από ένα «Καταχώρηση επιτυχής» που
        // έφευγε σε τέσσερα δευτερόλεπτα, χωρίς τρόπο να τις κρατήσει κανείς.
        // Παίρνουν εδώ ό,τι είχε ως τώρα μόνο η αποτυχία: διπλάσιο χρόνο στην
        // οθόνη και κουμπί αντιγραφής. Το επιτυχές αποτέλεσμα δεν αλλάζει —
        // μια προειδοποίηση δεν είναι σφάλμα, αλλά πρέπει να διαβαστεί.
        host.showDialogSnackBar(
          SnackBar(
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            duration: const Duration(seconds: 8),
          ),
          copyText: message,
        );
      }
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

  /// Ο κοινός κανόνας ελέγχου διπλού, δεμένος στους διαλόγους αυτής της οθόνης.
  ///
  /// `null` = ακύρωση από τον χρήστη· τότε καμία κλήση δεν σημαίνεται.
  Future<String?> _ticketIdWithoutDuplicate({
    required String candidate,
    required int duplicateCheckCallId,
  }) {
    return resolveTicketIdWithoutDuplicate(
      candidate: candidate,
      checkDuplicate: (ticketId) => _promptDuplicateTicketWarning(
        ticketId: ticketId,
        callId: duplicateCheckCallId,
      ),
      askForDifferentId: (currentTicketId) => _promptOptionalTicketId(
        initialTicketId: currentTicketId,
        title: 'Αλλαγή Ticket ID',
      ),
    );
  }

  /// Σημαίνει τις [callIds] ως καταχωρημένες και το ανακοινώνει με ένα μήνυμα.
  ///
  /// Το κενό [ticketId] σημαίνει «καταχωρημένη χωρίς αριθμό» — έγκυρη κατάσταση,
  /// γι' αυτό καθαρίζεται εδώ σε `null` αντί να το θυμάται κάθε καλών.
  Future<void> _markRegisteredAndAnnounce({
    required List<int> callIds,
    required String ticketId,
    String? comment,
  }) async {
    final notifier = host.ref.read(lansweeperSyncProvider.notifier);
    for (final callId in callIds) {
      await notifier.markRegistered(
        callId: callId,
        ticketId: ticketId.isEmpty ? null : ticketId,
        comment: comment,
      );
    }
    if (!host.mounted) return;
    host.showDialogSnackBar(
      SnackBar(
        content: Text(
          registrationSuccessMessage(count: callIds.length, ticketId: ticketId),
        ),
      ),
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
    final storedTicket = (item.call.lansweeperMainTicketId ?? '').trim();
    final requested = await _promptOptionalTicketId(
      initialTicketId: storedTicket.isEmpty ? null : storedTicket,
      title: title,
      subtitle: subtitle,
    );
    if (requested == null) return;

    final ticketId = await _ticketIdWithoutDuplicate(
      candidate: requested,
      duplicateCheckCallId: callId,
    );
    if (ticketId == null || !host.mounted) return;

    await _markRegisteredAndAnnounce(
      callIds: <int>[callId],
      ticketId: ticketId,
      comment: comment,
    );
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

    final ticketId = await _ticketIdWithoutDuplicate(
      candidate: input.ticketId,
      duplicateCheckCallId: callId,
    );
    if (ticketId == null || !host.mounted) return;

    await _markRegisteredAndAnnounce(
      callIds: <int>[callId],
      ticketId: ticketId,
      comment: input.comment,
    );
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

    final callIds = validItems.map((item) => item.call.id!).toList();
    final count = callIds.length;
    // Μόνο σε μία κλήση έχει νόημα το ήδη αποθηκευμένο ticket ως πρόταση· σε
    // πολλές θα ήταν αυθαίρετο ποιανής θα προτεινόταν.
    final storedTicket = count == 1
        ? (validItems.first.call.lansweeperMainTicketId ?? '').trim()
        : '';
    final requested = await _promptOptionalTicketId(
      initialTicketId: storedTicket.isEmpty ? null : storedTicket,
      title: count == 1 ? 'Καταχώρηση κλήσης' : 'Καταχώρηση $count κλήσεων',
      subtitle: count == 1
          ? 'Ο αριθμός ticket Lansweeper είναι προαιρετικός (π.χ. 17132).'
          : 'Ο αριθμός ticket Lansweeper είναι προαιρετικός και θα εφαρμοστεί σε όλες τις επιλεγμένες κλήσεις.',
    );
    if (requested == null) return;

    final ticketId = await _ticketIdWithoutDuplicate(
      candidate: requested,
      duplicateCheckCallId: callIds.first,
    );
    if (ticketId == null || !host.mounted) return;

    await _markRegisteredAndAnnounce(callIds: callIds, ticketId: ticketId);
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
