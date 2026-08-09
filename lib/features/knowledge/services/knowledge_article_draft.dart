import '../models/knowledge_article.dart';

/// Ετοιμάζει προσυμπληρωμένο άρθρο από τα στοιχεία μιας κλήσης.
///
/// Ένα σημείο για όλες τις αφετηρίες («Αποθήκευση ως γνώση» από την αναφορά
/// Lansweeper ή από την καρτέλα κλήσης), ώστε το άρθρο να γεννιέται πάντα με
/// τον ίδιο τρόπο: **σύμπτωμα το ωμό κείμενο, λύση το καθαρό**.
///
/// Η αντιστοίχιση δεν είναι αυθαίρετη. Το σύμπτωμα πρέπει να μείνει στη γλώσσα
/// του καλούντα γιατί εκεί θα ταιριάξει η επόμενη κλήση· η λύση πρέπει να είναι
/// η επεξεργασμένη γιατί εκείνη διαβάζεται μήνες μετά από άνθρωπο που δεν ήταν
/// στο τηλέφωνο.
abstract final class KnowledgeArticleDraft {
  KnowledgeArticleDraft._();

  /// Μέγιστο μήκος προτεινόμενου τίτλου· πιο πάνω παύει να είναι τίτλος.
  static const int maxTitleLength = 90;

  /// Κόβει έναν προτεινόμενο τίτλο σε μία γραμμή λογικού μήκους.
  static String shortenTitle(String value) {
    final single = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.length <= maxTitleLength) return single;
    final cut = single.substring(0, maxTitleLength);
    final lastSpace = cut.lastIndexOf(' ');
    final base = lastSpace > maxTitleLength ~/ 2
        ? cut.substring(0, lastSpace)
        : cut;
    return '${base.trimRight()}…';
  }

  static KnowledgeArticle fromCall({
    required String rawIssue,
    required String solution,
    String ticketTitle = '',
    int? categoryId,
    String? categoryName,
    int? sourceCallId,
  }) {
    return KnowledgeArticle(
      title: shortenTitle(
        ticketTitle.trim().isNotEmpty ? ticketTitle : rawIssue,
      ),
      symptom: rawIssue.trim(),
      solution: solution.trim(),
      categoryId: categoryId,
      categoryName: categoryName,
      sourceCallId: sourceCallId,
    );
  }
}
