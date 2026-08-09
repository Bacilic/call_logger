import '../../knowledge/models/knowledge_article.dart';
import '../../knowledge/providers/knowledge_provider.dart';
import '../../knowledge/services/knowledge_article_draft.dart';
import '../../knowledge/widgets/knowledge_article_dialog.dart';
import '../../knowledge/widgets/knowledge_duplicate_dialog.dart';
import 'lansweeper/lansweeper_report_item_mapper.dart';
import 'lansweeper_report_dialog.dart';

/// «Αποθήκευση ως γνώση»: η λύση μιας κλήσης γίνεται άρθρο Βάσης Γνώσης.
///
/// Συνεργάτης του [LansweeperReportDialogState] (Σύνθεση).
class LansweeperReportKnowledge {
  LansweeperReportKnowledge(this.host);

  final LansweeperReportDialogState host;

  /// Τα ωμά κείμενα των επιλεγμένων κλήσεων, χωρίς ημερομηνίες και ονόματα.
  ///
  /// Το άρθρο περιγράφει **είδος** βλάβης: ένα «[16/07 07:25] Φιλιώ Γκίλλα:»
  /// μπροστά από το σύμπτωμα θα το έδενε σε ένα περιστατικό και θα χαλούσε το
  /// ταίριασμα με την επόμενη κλήση.
  static String rawSymptomOf(List<ReportCallItem> selected) {
    final parts = <String>[];
    for (final item in selected) {
      final issue = (item.call.issue ?? '').trim();
      if (issue.isEmpty || parts.contains(issue)) continue;
      parts.add(issue);
    }
    return parts.join('\n');
  }

  /// Γιατί δεν μπορεί να αποθηκευτεί τώρα· `null` σημαίνει «μπορεί».
  String? saveDisabledReason(List<ReportCallItem> selected) {
    if (selected.isEmpty) {
      return 'Επιλέξτε πρώτα τις κλήσεις που αφορά η λύση.';
    }
    if (host.solutionController.text.trim().isEmpty) {
      return 'Συμπληρώστε τη «Λύση» — άρθρο χωρίς λύση δεν βοηθά κανέναν.';
    }
    if (rawSymptomOf(selected).isEmpty) {
      return 'Η κλήση δεν έχει σημειώσεις, οπότε λείπει το σύμπτωμα με το '
          'οποίο θα αναγνωριστεί ξανά το πρόβλημα.';
    }
    return null;
  }

  /// Το ήδη καταγεγραμμένο άρθρο για το ίδιο πρόβλημα, αν υπάρχει.
  ///
  /// Αποτυχία εδώ δεν εμποδίζει την αποθήκευση: χειρότερο αποτέλεσμα είναι ένα
  /// διπλό άρθρο, ενώ το να χαθεί η λύση επειδή κόλλησε ένα ερώτημα θα ήταν
  /// πραγματική ζημιά.
  Future<KnowledgeArticle?> _findExisting(String symptom, int? categoryId) async {
    try {
      final repo = await host.ref.read(knowledgeRepositoryProvider.future);
      return repo.findDuplicate(query: symptom, categoryId: categoryId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAsKnowledge(List<ReportCallItem> selected) async {
    if (saveDisabledReason(selected) != null) return;
    final primary = selected.first;
    final symptom = rawSymptomOf(selected);
    var draft = KnowledgeArticleDraft.fromCall(
      rawIssue: symptom,
      solution: host.solutionController.text,
      ticketTitle: host.titleController.text,
      categoryId: primary.call.categoryId,
      sourceCallId: primary.call.id,
    );

    // Πριν γεννηθεί δεύτερο άρθρο για κάτι ήδη γραμμένο: μια βάση γνώσης δεν
    // πεθαίνει από έλλειψη περιεχομένου, πεθαίνει από πέντε εκδοχές του ίδιου.
    final existing = await _findExisting(symptom, primary.call.categoryId);
    if (existing != null) {
      if (!host.mounted) return;
      final choice = await showKnowledgeDuplicateDialog(
        host.context,
        existing: existing,
      );
      if (choice == null || choice == KnowledgeDuplicateChoice.cancel) return;
      if (choice == KnowledgeDuplicateChoice.update) {
        draft = existing.copyWith(
          solution: draft.solution,
          sourceCallId: draft.sourceCallId,
        );
      }
    }

    if (!host.mounted) return;
    final id = await showKnowledgeArticleDialog(host.context, article: draft);
    if (id == null || !host.mounted) return;
    // Το άρθρο γεννήθηκε από πραγματικό περιστατικό — μετράει ως χρήση από την
    // πρώτη στιγμή, αλλιώς η νέα γνώση φαίνεται για πάντα αδοκίμαστη.
    await host.ref
        .read(knowledgeActionsProvider.notifier)
        .markUsed(<int>[id]);
  }
}
