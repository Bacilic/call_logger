import '../models/knowledge_article.dart';

/// Το αρχείο «Εξαγωγή για ΤΝ»: η οδηγία του χρήστη στην κορυφή και από κάτω
/// όλα τα άρθρα, το καθένα με τον αριθμό του.
///
/// Ο αριθμός είναι ο κωδικός του άρθρου στη βάση: όταν η ΤΝ απαντά «συγχώνευσε
/// το 3 με το 5», ο χρήστης βρίσκει αμέσως ποια άρθρα αλλάζει. Κενά πεδία δεν
/// γράφονται — μια γραμμή «Λέξεις-κλειδιά:» χωρίς τίποτα μόνο θα μπέρδευε.
String buildKnowledgeExportMarkdown({
  required String instruction,
  required List<KnowledgeArticle> articles,
}) {
  final out = StringBuffer()
    ..writeln(instruction.trim())
    ..writeln()
    ..writeln('---')
    ..writeln()
    ..writeln('Άρθρα: ${articles.length}');
  final ordered = [...articles]
    ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
  for (final article in ordered) {
    out
      ..writeln()
      ..writeln('## Άρθρο ${article.id ?? '—'}: ${article.title.trim()}');
    void line(String label, String? value) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) out.writeln('$label: $text');
    }

    line('Σύμπτωμα', article.symptom);
    line('Λύση', article.solution);
    line('Λέξεις-κλειδιά', article.tags);
    line('Κατηγορία', article.categoryName);
  }
  return out.toString();
}
