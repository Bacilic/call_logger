import '../../../core/utils/search_text_normalizer.dart';
import '../models/knowledge_article.dart';

/// Βαθμολογημένο άρθρο — το σκορ φαίνεται ώστε να μπορεί να ελεγχθεί.
typedef ScoredArticle = ({KnowledgeArticle article, int score});

/// Ταιριάζει μια τηλεγραφική περιγραφή κλήσης με άρθρα της Βάσης Γνώσης.
///
/// Δεν χρησιμοποιεί σημασιολογική αναζήτηση επίτηδες: για ~100 τυπικές βλάβες
/// ενός νοσοκομειακού IT, τα δομημένα κλειδιά (κατηγορία, λέξεις-κλειδιά) μαζί
/// με απλή τομή λέξεων δίνουν καλύτερο αποτέλεσμα από ό,τι θα δικαιολογούσε η
/// πολυπλοκότητα ενός μοντέλου embeddings.
///
/// Η σύγκριση γίνεται σε κανονικοποιημένο κείμενο (πεζά, χωρίς τόνους), γιατί
/// το σύμπτωμα γράφεται βιαστικά και ανορθόγραφα: «μαυρη οθονη» πρέπει να
/// βρίσκει το άρθρο που λέει «Μαύρη οθόνη».
abstract final class KnowledgeMatcher {
  KnowledgeMatcher._();

  /// Λέξεις που εμφανίζονται σχεδόν σε κάθε κλήση και δεν ξεχωρίζουν τίποτα.
  static const Set<String> stopWords = <String>{
    'και',
    'την',
    'τον',
    'της',
    'του',
    'των',
    'στο',
    'στη',
    'στην',
    'στον',
    'στα',
    'στισ',
    'στουσ',
    'δεν',
    'για',
    'απο',
    'ειναι',
    'ενα',
    'ενασ',
    'μια',
    'μιασ',
    'που',
    'πωσ',
    'θα',
    'σε',
    'με',
    'να',
    'το',
    'τα',
    'οι',
    'τι',
    'αν',
    'ολα',
    'ολο',
    'εχει',
    'εχω',
    'κανει',
    'παλι',
    'ξανα',
    'προσ',
    'μου',
    'μασ',
    'σασ',
  };

  /// Οι λέξεις που αξίζει να συγκριθούν: κανονικοποιημένες, χωρίς σημεία
  /// στίξης, χωρίς κοινότοπες, τουλάχιστον τριών χαρακτήρων.
  ///
  /// Οι αριθμοί μένουν ακόμη και με δύο ψηφία — ένας κωδικός εξοπλισμού ή μια
  /// έκδοση είναι από τα πιο διακριτικά στοιχεία μιας κλήσης.
  static Set<String> significantTokens(String text) {
    final normalized = SearchTextNormalizer.normalizeForSearch(
      text.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' '),
    );
    final tokens = <String>{};
    for (final token in normalized.split(' ')) {
      if (token.isEmpty) continue;
      if (stopWords.contains(token)) continue;
      final isNumber = RegExp(r'^\d+$').hasMatch(token);
      if (!isNumber && token.length < 3) continue;
      tokens.add(token);
    }
    return tokens;
  }

  /// Πόσο ταιριάζει ένα άρθρο με το ερώτημα· 0 σημαίνει «καθόλου».
  ///
  /// Τα βάρη ακολουθούν το πόσο σκόπιμο είναι κάθε σημάδι: την κατηγορία και
  /// τις λέξεις-κλειδιά τις όρισε άνθρωπος, άρα ζυγίζουν περισσότερο από μια
  /// τυχαία λέξη που έτυχε να υπάρχει και στις δύο περιγραφές.
  static int score({
    required KnowledgeArticle article,
    required String query,
    int? categoryId,
  }) {
    final queryTokens = significantTokens(query);
    if (queryTokens.isEmpty && categoryId == null) return 0;

    var total = 0;
    if (categoryId != null &&
        article.categoryId != null &&
        article.categoryId == categoryId) {
      total += 4;
    }

    for (final tag in article.tagList) {
      final tagTokens = significantTokens(tag);
      if (tagTokens.isEmpty) continue;
      if (tagTokens.every(queryTokens.contains)) total += 3;
    }

    final symptomTokens = significantTokens(article.symptom);
    total += 2 * symptomTokens.intersection(queryTokens).length;

    final titleTokens = significantTokens(article.title);
    total += titleTokens.intersection(queryTokens).length;

    return total;
  }

  /// Πάνω από αυτό το σκορ, δύο περιγραφές μιλούν για το ίδιο πρόβλημα.
  ///
  /// Χρησιμοποιείται μόνο στην ερώτηση «υπάρχει ήδη άρθρο γι' αυτό;» και είναι
  /// σκόπιμα αυστηρότερο από το [rank]: εκεί μια χαλαρή σχέση αξίζει να δειχτεί,
  /// εδώ μια λάθος ταύτιση θα έσβηνε δουλεμένη λύση.
  static const int duplicateScore = 8;

  /// Το άρθρο που περιγράφει ήδη αυτό το πρόβλημα, αν υπάρχει.
  static KnowledgeArticle? findDuplicate({
    required List<KnowledgeArticle> articles,
    required String query,
    int? categoryId,
  }) {
    final ranked = rank(
      articles: articles,
      query: query,
      categoryId: categoryId,
      limit: 1,
      minScore: duplicateScore,
    );
    return ranked.isEmpty ? null : ranked.first.article;
  }

  /// Τα άρθρα που ταιριάζουν, από το πιο σχετικό στο λιγότερο.
  ///
  /// Ισοβαθμία σπάει πρώτα με το πόσο έχει χρησιμοποιηθεί το άρθρο: όσα έχουν
  /// λύσει περισσότερα περιστατικά έχουν αποδείξει ότι δουλεύουν.
  static List<ScoredArticle> rank({
    required List<KnowledgeArticle> articles,
    required String query,
    int? categoryId,
    int limit = 3,
    int minScore = 2,
  }) {
    final scored = <ScoredArticle>[];
    for (final article in articles) {
      final value = score(
        article: article,
        query: query,
        categoryId: categoryId,
      );
      if (value < minScore) continue;
      scored.add((article: article, score: value));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byUsage = b.article.timesUsed.compareTo(a.article.timesUsed);
      if (byUsage != 0) return byUsage;
      return (a.article.id ?? 0).compareTo(b.article.id ?? 0);
    });
    return scored.length <= limit ? scored : scored.sublist(0, limit);
  }
}
