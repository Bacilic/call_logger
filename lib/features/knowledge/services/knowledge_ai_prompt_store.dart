import '../../../core/services/ai_prompt_template_syntax.dart';
import '../../../core/services/personal_ai_prompt.dart';
import '../../../core/services/profile_settings.dart';
import 'knowledge_ai_prompts.dart';

export '../../../core/services/personal_ai_prompt.dart';

/// Οι δύο προτροπές της Βάσης Γνώσης, προσωπικές όπως της Αναφοράς
/// Lansweeper: ο καθένας τις προσαρμόζει στη δική του ΤΝ.
enum KnowledgePrompt implements PersonalAiPrompt {
  improve(
    setting: ProfileSettingKeys.knowledgeImprovePrompt,
    profile: kKnowledgeImproveProfile,
    title: 'Προτροπή «Βελτίωση με ΤΝ»',
    description:
        'Ορίζει τι ζητά η ΤΝ όταν βελτιώνει ένα άρθρο της Βάσης Γνώσης. ',
  ),
  export(
    setting: ProfileSettingKeys.knowledgeExportPrompt,
    profile: kKnowledgeExportProfile,
    title: 'Οδηγία «Εξαγωγή για ΤΝ»',
    description:
        'Μπαίνει στην κορυφή του αρχείου εξαγωγής, πάνω από όλα τα άρθρα, και '
        'λέει στην ΤΝ τι να κάνει με αυτά. ',
  );

  const KnowledgePrompt({
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
