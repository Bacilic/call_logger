import '../../../../core/services/ai_model_cooldown_registry.dart';
import '../../../../core/services/ai_ticket_suggestion_service.dart';
import '../../../../core/services/lansweeper_sync_service.dart';
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
      AiFallbackReason.rateLimited => 'εξαντλημένη ποσόστωση (429)',
      AiFallbackReason.overloaded => 'υπερφόρτωση (503)',
      AiFallbackReason.cooldown => 'αναμονή ποσόστωσης (cooldown)',
      AiFallbackReason.modelNotFound =>
        'δεν υπάρχει ή δεν είναι διαθέσιμο (404)',
      AiFallbackReason.modelFailure => 'σφάλμα μοντέλου',
    };
    return 'Το μοντέλο «$fromModel» ($reasonText). '
        'Καλούμε το εφεδρικό μοντέλο: «$toModel».';
  }

  /// Τι διαβάζει ο χρήστης όταν η «Πρόταση ΤΝ» ξεκινά **ήδη** από το εφεδρικό,
  /// επειδή ο υπολογιστής θυμάται ότι το κύριο δεν πάει καλά.
  ///
  /// Λέει **την ακριβή αιτία**, όχι ένα γενικό «απέτυχε»: άλλο πράγμα να
  /// περιμένεις μισή ώρα για ποσόστωση, άλλο να έχεις γράψει λάθος όνομα
  /// μοντέλου και να το διορθώσεις σε πέντε δευτερόλεπτα.
  ///
  /// Όταν τον χρόνο τον έδωσε ο ίδιος ο διακομιστής, αναφέρεται ρητά ως δικός
  /// του: «σε 34 λεπτά» αλλάζει τι θα κάνεις μετά, ενώ η δική μας δεκάλεπτη
  /// εκτίμηση είναι απλώς πότε θα ξαναπροσπαθήσουμε.
  static String downgradedMessage({
    required AiModelDowntime downtime,
    required String activeModel,
    required DateTime now,
  }) {
    final remaining = remainingText(downtime.until, now);
    final usingFallback = activeModel.trim() != downtime.model.trim();
    final using = usingFallback ? ' Τρέχω στο εφεδρικό «$activeModel».' : '';

    final when = downtime.blocking
        ? 'Ο διακομιστής το δίνει ξανά $remaining.'
        : 'Το κύριο ξαναδοκιμάζεται $remaining.';

    return switch (downtime.reason) {
      AiModelDownReason.quotaExhausted =>
        'Η ποσόστωση του «${downtime.model}» εξαντλήθηκε. $when$using',
      AiModelDownReason.modelNotFound =>
        'Το μοντέλο «${downtime.model}» δεν υπάρχει ή δεν είναι διαθέσιμο με '
            'αυτό το κλειδί. Διορθώστε το όνομα στις Ρυθμίσεις.$using',
      AiModelDownReason.unavailable =>
        'Το μοντέλο «${downtime.model}» δεν αποκρίθηκε. $when$using',
    };
  }

  /// «σε 34 λεπτά» / «σε 1 λεπτό» / «σε λίγο» — ποτέ αρνητικό, ποτέ «σε 0».
  static String remainingText(DateTime until, DateTime now) {
    final seconds = until.difference(now).inSeconds;
    if (seconds < 60) return 'σε λίγο';
    final minutes = (seconds / 60).ceil();
    return minutes == 1 ? 'σε 1 λεπτό' : 'σε $minutes λεπτά';
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

  /// Ο αυτόματος τίτλος του αιτήματος — μία πηγή με την αποστολή προς το
  /// Lansweeper, ώστε ο έλεγχος «ο χρήστης έγραψε δικό του τίτλο;» να μη
  /// στηρίζεται σε δεύτερο, παράλληλο ορισμό.
  static String prefillTitle({required String category, required int? id}) =>
      LansweeperSyncService.autoTicketTitle(category: category, id: id);

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
