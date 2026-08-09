import '../models/knowledge_article.dart';

/// Μετατρέπει άρθρα Βάσης Γνώσης σε κείμενο για την προτροπή ΤΝ.
///
/// Το νόημα του `{Γνώση}` είναι να σταματήσει η ΤΝ να **επινοεί** λύσεις: αντί
/// να μαντεύει τι θα μπορούσε να λύσει το πρόβλημα, βλέπει τι έχει όντως δουλέψει
/// σε αυτό το νοσοκομείο και το επαναλαμβάνει με το δικό σας λεξιλόγιο.
abstract final class KnowledgePromptContext {
  KnowledgePromptContext._();

  /// Πόσο κείμενο λύσης μπαίνει ανά άρθρο· πιο πολύ πνίγει την προτροπή.
  static const int maxSolutionChars = 400;

  static String _clip(String value) {
    final single = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.length <= maxSolutionChars) return single;
    return '${single.substring(0, maxSolutionChars).trimRight()}…';
  }

  /// Κενό κείμενο όταν δεν υπάρχουν άρθρα — τότε το προαιρετικό block
  /// `{@Γνώση}…{@/Γνώση}` αφαιρείται ολόκληρο από την προτροπή.
  static String format(List<KnowledgeArticle> articles) {
    final usable = articles.where((a) => a.isUsable).toList();
    if (usable.isEmpty) return '';
    final lines = <String>[];
    for (final article in usable) {
      lines.add('- Σύμπτωμα: ${_clip(article.symptom)}');
      lines.add('  Λύση: ${_clip(article.solution)}');
    }
    return lines.join('\n');
  }
}
