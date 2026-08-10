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

  /// Γιατί δεν μπορεί να γίνει άρθρο· `null` σημαίνει «μπορεί».
  ///
  /// Καθαρή λογική, χωρίς εξάρτηση από τον διάλογο: η ίδια απόφαση κρίνει και
  /// το κουμπί και την ίδια την αποθήκευση. Ο **τίτλος δεν ελέγχεται** — όταν
  /// λείπει, το άρθρο τον παράγει από το σύμπτωμα, οπότε ένας έλεγχος θα
  /// μπλόκαρε κάτι που δεν μπορεί να αποτύχει.
  static String? disabledReasonFor({
    required int selectedCount,
    required String symptom,
    required String solution,
  }) {
    if (selectedCount == 0) {
      return 'Επιλέξτε πρώτα την κλήση που αφορά η λύση.';
    }
    // Το άρθρο κρατά ΜΙΑ κλήση προέλευσης και περιγράφει ένα είδος βλάβης· με
    // πολλές επιλεγμένες θα διαλέγαμε σιωπηλά την πρώτη και το σύμπτωμα θα
    // γινόταν συνονθύλευμα από διαφορετικά περιστατικά.
    if (selectedCount > 1) {
      return 'Επιλέξτε μία μόνο κλήση — το άρθρο περιγράφει ένα είδος βλάβης, '
          'όχι πολλά περιστατικά.';
    }
    if (solution.trim().isEmpty) {
      return 'Συμπληρώστε τη «Λύση» — άρθρο χωρίς λύση δεν βοηθά κανέναν.';
    }
    if (symptom.trim().isEmpty) {
      return 'Συμπληρώστε την περιγραφή του προβλήματος — είναι το σύμπτωμα με '
          'το οποίο θα αναγνωριστεί ξανά η βλάβη.';
    }
    return null;
  }

  /// Η ίδια απόφαση για τα **τρέχοντα** πεδία της φόρμας.
  String? saveDisabledReason(List<ReportCallItem> selected) =>
      disabledReasonFor(
        selectedCount: selected.length,
        symptom: host.notesController.text,
        solution: host.solutionController.text,
      );

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
    // Σύμπτωμα και λύση από τα **πεδία της φόρμας**, όχι από την αποθηκευμένη
    // κλήση: ό,τι μόλις διόρθωσε ο χρήστης εδώ είναι η διατύπωση που θέλει να
    // κρατήσει. Διαβάζοντας την κλήση, το άρθρο έπαιρνε την παλιά γραφή.
    final symptom = host.notesController.text;
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
