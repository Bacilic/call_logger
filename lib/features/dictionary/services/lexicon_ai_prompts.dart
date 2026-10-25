// Ο μαζικός έλεγχος λέξεων του Λεξικού από την ΤΝ: η προτροπή και η ανάγνωση
// της απάντησης. Καθαρή λογική — χωρίς UI, χωρίς δίκτυο.
//
// Αποφάσεις Διευθυντή 24/10/2026: η προτροπή είναι επεξεργάσιμη· το κείμενο
// από κάτω είναι μόνο η εργοστασιακή της τιμή, εγκεκριμένη ως έχει.

import '../../../core/services/ai_prompt_template_syntax.dart';
import '../../../core/services/gemini_json_request.dart';

/// Πόσες λέξεις φεύγουν σε μία ερώτηση· με περισσότερες η απάντηση της ΤΝ
/// χάνει αξιοπιστία.
const int kLexiconAiReviewBatchSize = 200;

/// Η εργοστασιακή προτροπή του μαζικού ελέγχου.
const String kDefaultLexiconReviewPrompt = '''
Είσαι επιμελητής του λεξικού ορθογραφίας που χρησιμοποιεί η τεχνική υποστήριξη ενός νοσοκομείου. Οι παρακάτω λέξεις ήρθαν από πηγή που δεν είναι αξιόπιστη: κάποιες είναι σωστές, κάποιες έχουν ορθογραφικό λάθος και κάποιες δεν είναι λέξεις.

Για κάθε λέξη αποφάσισε ένα από τα τρία:
- correct: η λέξη υπάρχει και γράφεται σωστά, μαζί με τον τόνο της.
- fix: η λέξη υπάρχει αλλά γράφεται λάθος· δώσε τη σωστή μορφή στο suggestion.
- delete: δεν είναι λέξη (κομμάτι λέξης, τυχαία γράμματα, λάθος χωρίς προφανή διόρθωση).

Κανόνες:
- Δέξου ελληνικές και αγγλικές λέξεις.
- Ονόματα, επώνυμα, ονόματα εταιρειών και προϊόντων, καθώς και τεχνικές συντομογραφίες (π.χ. API, ATM, VPN) είναι σωστά.
- Ελληνική λέξη που θέλει τόνο και δεν τον έχει, ή τον έχει σε λάθος συλλαβή, είναι fix.
- Κράτα τα κεφαλαία όπως είναι, εκτός αν η λέξη είναι κύριο όνομα που γράφτηκε με μικρά.
- Βάλε "sure": false όταν δεν είσαι βέβαιος (σπάνια λέξη, πιθανό επώνυμο, διφορούμενη περίπτωση).

Λέξεις:
{Λέξεις}

Απάντησε ΜΟΝΟ με έγκυρο JSON (χωρίς markdown), με μία εγγραφή για κάθε αριθμό:
{"results": [{"n": 1, "verdict": "correct", "suggestion": "", "sure": true}]}''';

/// Ο μαζικός έλεγχος: αριθμημένες λέξεις μέσα, μία ετυμηγορία ανά αριθμό πίσω.
const AiPromptProfile kLexiconReviewProfile = AiPromptProfile(
  placeholders: [(token: '{Λέξεις}', label: 'Λέξεις')],
  jsonResponseKeys: ['results', 'n', 'verdict', 'suggestion'],
  jsonKeyLabels: {
    'results': 'αποτελέσματα',
    'n': 'αριθμό λέξης',
    'verdict': 'ετυμηγορία',
    'suggestion': 'σωστή μορφή',
  },
  responseBlueprint:
      '{"results": [{"n": 1, "verdict": "correct", "suggestion": "", "sure": true}]}',
  defaultTemplate: kDefaultLexiconReviewPrompt,
);

/// Τι αποφάσισε η ΤΝ για μία λέξη.
enum LexiconAiVerdictKind { correct, fix, delete }

class LexiconAiVerdict {
  const LexiconAiVerdict({
    required this.kind,
    this.suggestion = '',
    required this.sure,
  });

  final LexiconAiVerdictKind kind;

  /// Η σωστή μορφή — μόνο στη [LexiconAiVerdictKind.fix].
  final String suggestion;
  final bool sure;
}

/// Η προτροπή για τις [words], αριθμημένες από το 1 με τη σειρά τους. Κενό
/// [template] σημαίνει την εργοστασιακή.
String buildLexiconReviewPrompt({
  required String template,
  required List<String> words,
}) {
  final source = template.trim().isEmpty
      ? kLexiconReviewProfile.defaultTemplate
      : template;
  final lines = [
    for (var i = 0; i < words.length; i++) '${i + 1}. ${words[i].trim()}',
  ].join('\n');
  return source.replaceAll('{Λέξεις}', lines);
}

/// Οι ετυμηγορίες της απάντησης, ανά αριθμό λέξης (από το 1).
///
/// Ό,τι δεν διαβάζεται με βεβαιότητα παραλείπεται — άγνωστη ετυμηγορία,
/// διόρθωση χωρίς σωστή μορφή, αριθμός εκτός λίστας: η λέξη μένει ως ήταν.
/// `null` όταν η απάντηση δεν έχει ούτε μία ετυμηγορία που να διαβάζεται.
Map<int, LexiconAiVerdict>? parseLexiconReviewResponse(
  String text, {
  required int wordCount,
}) {
  final decoded = GeminiJsonRequest.decodeObject(text);
  final results = decoded?['results'];
  if (results is! List) return null;

  final verdicts = <int, LexiconAiVerdict>{};
  for (final item in results) {
    if (item is! Map) continue;
    final n = _readInt(item['n']);
    if (n == null || n < 1 || n > wordCount) continue;
    final kind = switch (item['verdict']?.toString().trim().toLowerCase()) {
      'correct' => LexiconAiVerdictKind.correct,
      'fix' => LexiconAiVerdictKind.fix,
      'delete' => LexiconAiVerdictKind.delete,
      _ => null,
    };
    if (kind == null) continue;
    final suggestion = item['suggestion']?.toString().trim() ?? '';
    if (kind == LexiconAiVerdictKind.fix && suggestion.isEmpty) continue;
    verdicts[n] = LexiconAiVerdict(
      kind: kind,
      suggestion: kind == LexiconAiVerdictKind.fix ? suggestion : '',
      sure: _readBool(item['sure']),
    );
  }
  return verdicts.isEmpty ? null : verdicts;
}

int? _readInt(Object? value) => switch (value) {
  int v => v,
  num v when v == v.roundToDouble() => v.toInt(),
  String v => int.tryParse(v.trim()),
  _ => null,
};

/// Μόνο ρητό «ναι» μετρά ως βέβαιο: ό,τι λείπει ή δεν διαβάζεται θέλει ματιά.
bool _readBool(Object? value) => switch (value) {
  bool v => v,
  String v => v.trim().toLowerCase() == 'true',
  _ => false,
};
