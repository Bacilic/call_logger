import '../../../../core/services/ai_ticket_suggestion_service.dart';
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
    );
  }

  static String prefillTitle({required String category, required int? id}) {
    final idSuffix = id != null ? ' #$id' : '';
    return category.isEmpty ? 'Κλήση$idSuffix' : '[$category]$idSuffix';
  }
}
