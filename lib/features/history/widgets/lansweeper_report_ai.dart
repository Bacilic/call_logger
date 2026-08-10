import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/services/ai_ticket_suggestion_service.dart';
import '../../../core/utils/run_after_next_frame.dart';
import '../../knowledge/providers/knowledge_provider.dart';
import '../../knowledge/services/knowledge_prompt_context.dart';
import '../providers/ai_ticket_suggestion_provider.dart';
import '../providers/gemini_settings_provider.dart';
import 'lansweeper/lansweeper_ai_presenter.dart';
import 'lansweeper/lansweeper_ai_prompt_preview_dialog.dart';
import 'lansweeper/lansweeper_report_item_mapper.dart';
import 'lansweeper_report_dialog.dart';

/// Προσυμπλήρωση φόρμας και προτάσεις AI (Gemini) με cooldown/αυτόματη επανυποβολή.
///
/// Συνεργάτης του [LansweeperReportDialogState] (Σύνθεση).
class LansweeperReportAi {
  LansweeperReportAi(this.host);

  final LansweeperReportDialogState host;

  /// Προσυμπληρώνει τη φόρμα από τις επιλεγμένες κλήσεις.
  ///
  /// Καλείται **μέσα από το build** του διαλόγου, μόλις αλλάξει η επιλογή. Η
  /// γραφή σε `TextEditingController` ειδοποιεί τους ακροατές του, οπότε εκεί
  /// είναι απαγορευμένη: όποιος ακούει θα ζητούσε ανανέωση μέσα σε φάση
  /// χτισίματος και η εφαρμογή θα έπεφτε με «setState() called during build».
  /// Το κλειδί μπαίνει **συγχρόνως** (αλλιώς θα προγραμματίζαμε την ίδια
  /// προσυμπλήρωση σε κάθε ενδιάμεσο frame), η γραφή αναβάλλεται.
  void prefillForm(ReportCallItem primary, List<ReportCallItem> selected) {
    final signature = LansweeperReportItemMapper.selectedKeysSignature(
      selected,
    );
    if (host.lastPrefilledKey == signature) return;
    host.lastPrefilledKey = signature;

    final title = LansweeperAiPresenter.prefillTitle(
      category: (primary.call.category ?? '').trim(),
      id: primary.call.id,
    );
    final notes = LansweeperReportItemMapper.combinedSelectedNotes(selected);
    // Η λύση φορτώνεται από τις ίδιες τις κλήσεις, όπως η περιγραφή: από τη
    // στιγμή που η καρτέλα επεξεργασίας δέχεται λύση, η φόρμα δεν είναι πια η
    // μόνη πηγή της. Καρφωτό κενό εδώ σήμαινε ότι δουλεμένη λύση δεν έφτανε
    // ποτέ στο ticket και ότι το «Αποθήκευση ως γνώση» έμενε ανενεργό.
    final solution = LansweeperReportItemMapper.combinedSelectedSolutions(
      selected,
    );

    runNowOrAfterFrame(() {
      if (!host.mounted) return;
      host.titleController.text = title;
      host.notesController.text = notes;
      host.solutionController.text = solution;
      // Άλλη επιλογή κλήσεων, άλλο περιστατικό: η προηγούμενη πρόταση ΤΝ δεν το
      // αφορά, οπότε ό,τι σταλεί από δω και πέρα μετράει ως χειρόγραφο.
      host.aiSuggestedNotes = null;
      host.aiSuggestedSolution = null;
    });
  }

  /// Το ερώτημα αναζήτησης γνώσης: τα κείμενα των κλήσεων, χωρίς ημερομηνίες
  /// και ονόματα.
  ///
  /// Τα άρθρα κρατούν το σύμπτωμα στη γλώσσα του καλούντα· ένα «[16/07 07:25]
  /// Φιλιώ Γκίλλα:» μπροστά θα το έδενε σε ένα περιστατικό και θα χαλούσε το
  /// ταίριασμα.
  static String _knowledgeQueryOf(List<ReportCallItem> selected) {
    final parts = <String>[];
    for (final item in selected) {
      final issue = (item.call.issue ?? '').trim();
      if (issue.isEmpty || parts.contains(issue)) continue;
      parts.add(issue);
    }
    return parts.join('\n');
  }

  /// Τα σχετικά άρθρα Βάσης Γνώσης, έτοιμα για το `{Γνώση}` της προτροπής.
  ///
  /// Αν το ταίριασμα αποτύχει, η προτροπή φεύγει όπως πάντα — η γνώση είναι
  /// μπόνους, όχι προϋπόθεση, και δεν επιτρέπεται να μπλοκάρει την πρόταση ΤΝ.
  Future<String> _knowledgeContextFor(List<ReportCallItem> selected) async {
    if (selected.isEmpty) return '';
    final query = _knowledgeQueryOf(selected);
    if (query.trim().isEmpty) return '';
    try {
      final articles = await host.ref.read(
        relevantKnowledgeProvider((
          query: query,
          categoryId: selected.first.call.categoryId,
        )).future,
      );
      return KnowledgePromptContext.format(articles);
    } catch (_) {
      return '';
    }
  }

  Future<String> _buildAiPromptForSelected(List<ReportCallItem> selected) async {
    final service = host.ref.read(aiTicketSuggestionServiceProvider);
    return service.buildPrompt(await _aiPromptInputs(selected));
  }

  Future<AiTicketSuggestionRequest> _aiPromptInputs(
    List<ReportCallItem> selected,
  ) async {
    return LansweeperAiPresenter.buildRequest(
      selected: selected,
      titleText: host.titleController.text,
      notesText: host.notesController.text,
      solutionText: host.solutionController.text,
      knowledgeText: await _knowledgeContextFor(selected),
    );
  }

  Future<void> showAiPromptPreview(List<ReportCallItem> selected) async {
    if (selected.isEmpty || host.aiSuggestRunning || isAiCooldownActive) {
      return;
    }
    final prompt = await _buildAiPromptForSelected(selected);
    if (!host.mounted) return;
    await showLansweeperAiPromptPreviewDialog(host.context, promptText: prompt);
  }

  bool get isAiCooldownActive => LansweeperAiPresenter.isCooldownActive(
    host.aiCooldownUntil,
    DateTime.now(),
  );

  int? get aiCooldownRemainingSeconds =>
      LansweeperAiPresenter.cooldownRemainingSeconds(
        host.aiCooldownUntil,
        DateTime.now(),
      );

  void cancelAiAutoResubmit() {
    host.aiAutoResubmitArmed = false;
    _stopAiCooldownTicker(clearState: true);
    host.notifyReportChanged();
  }

  void _stopAiCooldownTicker({bool clearState = false}) {
    host.aiCooldownTicker?.cancel();
    host.aiCooldownTicker = null;
    if (clearState) {
      host.aiCooldownUntil = null;
      host.aiCooldownModel = null;
    }
  }

  void _startAiCooldownTicker({
    required DateTime until,
    required String model,
    required List<ReportCallItem> selected,
  }) {
    _stopAiCooldownTicker();
    host.aiCooldownUntil = until;
    host.aiCooldownModel = model;
    host.aiLastSuggestSelection = selected;
    host.aiAutoResubmitArmed = host.ref.read(geminiAutoResubmitEnabledProvider);

    void tick() {
      if (!host.mounted) return;
      if (!isAiCooldownActive) {
        _stopAiCooldownTicker(clearState: true);
        final shouldResubmit =
            host.aiAutoResubmitArmed && host.aiLastSuggestSelection != null;
        host.aiAutoResubmitArmed = false;
        host.notifyReportChanged();
        if (shouldResubmit && host.mounted) {
          unawaited(suggestWithAi(host.aiLastSuggestSelection!));
        }
        return;
      }
      host.notifyReportChanged();
    }

    tick();
    host.aiCooldownTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => tick(),
    );
  }

  Future<void> suggestWithAi(List<ReportCallItem> selected) async {
    if (host.aiSuggestRunning || selected.isEmpty || isAiCooldownActive) {
      return;
    }

    final service = host.ref.read(aiTicketSuggestionServiceProvider);
    final configError = service.validateConfiguration();
    if (configError != null) {
      if (!host.mounted) return;
      host.showDialogSnackBar(SnackBar(content: Text(configError)));
      return;
    }

    final request = await _aiPromptInputs(selected);
    if (!host.mounted) return;
    host.aiLastSuggestSelection = selected;
    host.aiAutoResubmitArmed = false;

    host.aiSuggestRunning = true;
    host.notifyReportChanged();
    final client = http.Client();
    host.aiSuggestClient = client;
    try {
      final result = await service.suggest(
        request,
        client: client,
        onModelAttempt: (model) {
          if (!host.mounted) return;
          _stopAiSuggestTicker();
          _startAiSuggestTicker(model: model);
        },
        onFallback: (fromModel, toModel, reason) {
          if (!host.mounted) return;
          host.showDialogSnackBar(
            SnackBar(
              content: Text(
                LansweeperAiPresenter.fallbackMessage(
                  fromModel: fromModel,
                  toModel: toModel,
                  reason: reason,
                ),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        },
      );

      if (!host.mounted) return;
      host.aiAutoResubmitArmed = false;
      host.titleController.text = result.title;
      host.notesController.text = result.description;
      host.solutionController.text = result.solution;
      host.aiSuggestedNotes = result.description;
      host.aiSuggestedSolution = result.solution;
      host.notifyReportChanged();
    } on AiSuggestionException catch (e) {
      if (!host.mounted) return;
      host.aiAutoResubmitArmed = false;

      if (e.scope == AiSuggestionFailureScope.infrastructure) {
        host.showDialogSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 8),
          ),
          copyText: e.message,
        );
        return;
      }

      host.showDialogSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 8),
        ),
        copyText: e.message,
      );

      if (e.retryAvailableAt != null) {
        _startAiCooldownTicker(
          until: e.retryAvailableAt!,
          model: e.waitingModel ?? host.aiCurrentModel ?? '',
          selected: selected,
        );
      }
    } catch (e) {
      if (!host.mounted) return;
      host.aiAutoResubmitArmed = false;
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      host.showDialogSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 8),
        ),
        copyText: errorMessage,
      );
    } finally {
      host.aiSuggestClient = null;
      client.close();
      _stopAiSuggestTicker();
      if (host.mounted) {
        host.aiSuggestRunning = false;
        host.notifyReportChanged();
      }
    }
  }

  void _startAiSuggestTicker({required String model}) {
    host.aiSuggestStopwatch
      ..reset()
      ..start();
    host.aiSuggestRunning = true;
    host.aiSuggestElapsedSeconds = 0;
    host.aiCurrentModel = model;
    host.notifyReportChanged();
    host.aiSuggestTicker = Timer.periodic(const Duration(milliseconds: 33), (
      _,
    ) {
      if (!host.mounted) return;
      host.aiSuggestElapsedSeconds =
          host.aiSuggestStopwatch.elapsedMilliseconds / 1000;
      host.notifyReportChanged();
    });
  }

  void _stopAiSuggestTicker() {
    host.aiSuggestTicker?.cancel();
    host.aiSuggestTicker = null;
    host.aiSuggestStopwatch.stop();
  }
}
