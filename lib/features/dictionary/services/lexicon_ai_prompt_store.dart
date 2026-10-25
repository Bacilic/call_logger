import '../../../core/services/ai_prompt_template_syntax.dart';
import '../../../core/services/personal_ai_prompt.dart';
import '../../../core/services/profile_settings.dart';
import '../../../core/services/spelling_lookup_gemini_service.dart';
import 'lexicon_ai_prompts.dart';

export '../../../core/services/personal_ai_prompt.dart';

/// Οι δύο προτροπές της ΤΝ στο Λεξικό, προσωπικές όπως όλες οι προτροπές.
enum LexiconPrompt implements PersonalAiPrompt {
  word(
    setting: ProfileSettingKeys.lexiconWordPrompt,
    profile: kSpellingLookupProfile,
    title: 'Προτροπή «Ερώτηση ΤΝ»',
    description:
        'Ορίζει τι ζητά η ΤΝ όταν ελέγχει την ορθογραφία μίας λέξης στο '
        'πάνελ «Ορθογραφία». ',
  ),
  review(
    setting: ProfileSettingKeys.lexiconReviewPrompt,
    profile: kLexiconReviewProfile,
    title: 'Προτροπή «Έλεγχος με ΤΝ»',
    description:
        'Ορίζει τι ζητά η ΤΝ όταν ελέγχει μαζικά τις επιλεγμένες λέξεις του '
        'Λεξικού. Οι λέξεις μπαίνουν αριθμημένες, μία σε κάθε γραμμή. ',
  );

  const LexiconPrompt({
    required this.setting,
    required this.profile,
    required this.title,
    required this.description,
  });

  @override
  final ProfileSettingKey setting;
  @override
  final AiPromptProfile profile;
  @override
  final String title;
  @override
  final String description;
}
