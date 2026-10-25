// Οι δύο προτροπές ΤΝ της Βάσης Γνώσης: βελτίωση ενός άρθρου και εξαγωγή
// όλης της βάσης. Καθαρή λογική — χωρίς UI, χωρίς δίκτυο.
//
// Αποφάσεις Διευθυντή 23/10/2026: καμία προτροπή δεμένη στον κώδικα — και οι
// δύο επεξεργάσιμες όπως της Αναφοράς Lansweeper. Τα κείμενα από κάτω είναι
// μόνο οι εργοστασιακές τους τιμές, εγκεκριμένες ως έχουν.

import '../../../core/services/ai_prompt_template_syntax.dart';
import '../../../core/services/gemini_json_request.dart';

/// Η εργοστασιακή προτροπή της «Βελτίωσης με ΤΝ».
const String kDefaultKnowledgeImprovePrompt =
    '''Βελτίωσε τη διατύπωση του παρακάτω άρθρου βάσης γνώσης, χωρίς να αλλάξεις το νόημα, και πρότεινε λέξεις-κλειδιά.
Τίτλος: {Τίτλος}
Σύμπτωμα: {Σύμπτωμα}
Λύση: {Λύση}
{@Λέξεις-κλειδιά}Τρέχουσες λέξεις-κλειδιά: {Λέξεις-κλειδιά}{@/Λέξεις-κλειδιά}
Απάντησε ΜΟΝΟ σε JSON χωρίς markdown: {"title":"...","symptom":"...","solution":"...","tags":"..."}''';

/// Η εργοστασιακή οδηγία στην κορυφή του αρχείου «Εξαγωγή για ΤΝ».
const String kDefaultKnowledgeExportPrompt =
    'Παρακάτω είναι όλα τα άρθρα μιας βάσης γνώσης τεχνικής υποστήριξης, το '
    'καθένα με τον αριθμό του. Πρότεινε συγχωνεύσεις άρθρων που περιγράφουν '
    'το ίδιο πρόβλημα και διασπάσεις άρθρων που περιγράφουν περισσότερα από '
    'ένα. Για κάθε πρόταση γράψε τους αριθμούς των άρθρων και τι να γίνει.';

/// Η «Βελτίωση με ΤΝ»: τα πεδία του άρθρου μέσα, τα ίδια πεδία πίσω σε JSON.
const AiPromptProfile kKnowledgeImproveProfile = AiPromptProfile(
  placeholders: [
    (token: '{Τίτλος}', label: 'Τίτλος'),
    (token: '{Σύμπτωμα}', label: 'Σύμπτωμα'),
    (token: '{Λύση}', label: 'Λύση'),
    (token: '{Λέξεις-κλειδιά}', label: 'Λέξεις-κλειδιά'),
  ],
  jsonResponseKeys: ['title', 'symptom', 'solution', 'tags'],
  jsonKeyLabels: {
    'title': 'τίτλο',
    'symptom': 'σύμπτωμα',
    'solution': 'λύση',
    'tags': 'λέξεις-κλειδιά',
  },
  defaultTemplate: kDefaultKnowledgeImprovePrompt,
);

/// Η οδηγία της εξαγωγής: τη διαβάζει εξωτερική ΤΝ μαζί με τα άρθρα που
/// ακολουθούν, άρα ούτε σήματα ούτε απάντηση JSON.
const AiPromptProfile kKnowledgeExportProfile = AiPromptProfile(
  placeholders: [],
  jsonResponseKeys: [],
  defaultTemplate: kDefaultKnowledgeExportPrompt,
);

/// Η προτροπή που φεύγει για ένα άρθρο: σήματα συμπληρωμένα, κενά τμήματα
/// (π.χ. χωρίς λέξεις-κλειδιά) αφαιρεμένα. Κενό πρότυπο σημαίνει εργοστασιακό.
String buildKnowledgeImprovePrompt({
  required String template,
  required String title,
  required String symptom,
  required String solution,
  required String tags,
}) {
  const profile = kKnowledgeImproveProfile;
  final values = <String, String>{
    '{Τίτλος}': title.trim(),
    '{Σύμπτωμα}': symptom.trim(),
    '{Λύση}': solution.trim(),
    '{Λέξεις-κλειδιά}': tags.trim(),
  };
  var prompt = template.trim().isEmpty ? profile.defaultTemplate : template;
  prompt = AiPromptTemplateSyntax.stripEmptyOptionalBlocks(prompt, {
    for (final entry in values.entries)
      if (entry.value.isEmpty) entry.key,
  });
  for (final entry in values.entries) {
    prompt = prompt.replaceAll(entry.key, entry.value);
  }
  prompt = AiPromptTemplateSyntax.stripBlockMarkers(prompt, profile: profile);
  return AiPromptTemplateSyntax.compactWhitespace(prompt);
}

/// Ό,τι πρότεινε η ΤΝ για ένα άρθρο. Πεδίο `null`: η ΤΝ δεν το έστειλε, και
/// το αντίστοιχο πεδίο της φόρμας μένει όπως είναι.
typedef KnowledgeImproveSuggestion = ({
  String? title,
  String? symptom,
  String? solution,
  String? tags,
});

/// Διαβάζει την απάντηση της ΤΝ. `null` όταν δεν είναι JSON ή δεν φέρνει
/// κανένα από τα πεδία — τότε δεν αλλάζει τίποτα στη φόρμα.
///
/// Τις λέξεις-κλειδιά η ΤΝ τις στέλνει άλλοτε ως κείμενο και άλλοτε ως λίστα·
/// η φόρμα τις θέλει χωρισμένες με κόμμα.
KnowledgeImproveSuggestion? parseKnowledgeImproveResponse(String text) {
  final decoded = GeminiJsonRequest.decodeObject(text);
  if (decoded == null) return null;
  String? field(String key) {
    final value = decoded[key];
    if (value == null) return null;
    final text = value is List
        ? value
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .join(', ')
        : value.toString().trim();
    return text.isEmpty ? null : text;
  }

  final suggestion = (
    title: field('title'),
    symptom: field('symptom'),
    solution: field('solution'),
    tags: field('tags'),
  );
  final empty =
      suggestion.title == null &&
      suggestion.symptom == null &&
      suggestion.solution == null &&
      suggestion.tags == null;
  return empty ? null : suggestion;
}
