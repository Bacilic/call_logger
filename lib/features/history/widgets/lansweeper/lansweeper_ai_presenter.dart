import '../../../../core/services/ai_ticket_suggestion_service.dart';
import '../../../calls/models/call_refined_source.dart';
import 'lansweeper_report_item_mapper.dart';

class LansweeperAiPresenter {
  LansweeperAiPresenter._();

  static String fallbackMessage({
    required String fromModel,
    required String toModel,
    required AiFallbackReason reason,
  }) {
    final reasonText = switch (reason) {
      AiFallbackReason.rateLimited => 'ποσόστωση (429)',
      AiFallbackReason.overloaded => 'υπερφόρτωση (503)',
      AiFallbackReason.cooldown => 'αναμονή ποσόστωσης (cooldown)',
      AiFallbackReason.modelFailure => 'σφάλμα μοντέλου',
    };
    return 'Το μοντέλο «$fromModel» ($reasonText). '
        'Καλούμε το εφεδρικό μοντέλο: «$toModel».';
  }

  static bool isCooldownActive(DateTime? until, DateTime now) =>
      until != null && now.isBefore(until);

  static int? cooldownRemainingSeconds(DateTime? until, DateTime now) {
    if (until == null) return null;
    final remaining = until.difference(now).inSeconds;
    if (remaining <= 0) return null;
    return remaining;
  }

  static AiTicketSuggestionRequest buildRequest({
    required List<ReportCallItem> selected,
    required String titleText,
    required String notesText,
    required String solutionText,
    String knowledgeText = '',
  }) {
    return AiTicketSuggestionRequest(
      callerText: LansweeperReportItemMapper.combinedUniqueCallField(
        selected,
        (call) => call.callerText,
      ),
      equipmentText: LansweeperReportItemMapper.combinedUniqueCallField(
        selected,
        (call) => call.equipmentText,
      ),
      departmentText: LansweeperReportItemMapper.combinedUniqueCallField(
        selected,
        (call) => call.departmentText,
      ),
      category: LansweeperReportItemMapper.combinedUniqueCallField(
        selected,
        (call) => call.category,
      ),
      issue: LansweeperReportItemMapper.combinedAiIssue(selected),
      titleText: titleText,
      notesText: notesText,
      solutionText: solutionText,
      knowledgeText: knowledgeText,
    );
  }

  static String prefillTitle({required String category, required int? id}) {
    final idSuffix = id != null ? ' #$id' : '';
    return category.isEmpty ? 'Κλήση$idSuffix' : '[$category]$idSuffix';
  }

  /// Πώς προέκυψε το κείμενο που φεύγει τώρα προς το Lansweeper.
  ///
  /// Συγκρίνει με ό,τι γύρισε η τελευταία «Πρόταση ΤΝ»: ίδιο κείμενο σημαίνει
  /// ότι η πρόταση στάλθηκε ως έχει, αλλαγμένο σημαίνει ότι πέρασε από τα χέρια
  /// του χρήστη, και απουσία πρότασης σημαίνει χειρόγραφο.
  static String refinedSource({
    required String? aiProblem,
    required String? aiSolution,
    required String problem,
    required String solution,
  }) {
    if (aiProblem == null && aiSolution == null) {
      return CallRefinedSource.manual;
    }
    final sameProblem = (aiProblem ?? '').trim() == problem.trim();
    final sameSolution = (aiSolution ?? '').trim() == solution.trim();
    return sameProblem && sameSolution
        ? CallRefinedSource.ai
        : CallRefinedSource.aiEdited;
  }
}
