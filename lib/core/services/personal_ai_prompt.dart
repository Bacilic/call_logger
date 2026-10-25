import 'ai_prompt_template_syntax.dart';
import 'profile_settings.dart';
import 'scoped_settings.dart';

/// Μια προτροπή ΤΝ που ο καθένας προσαρμόζει στη δική του ΤΝ: ζει στις
/// προσωπικές ρυθμίσεις, και όταν λείπει ισχύει η εργοστασιακή του [profile].
abstract interface class PersonalAiPrompt {
  ProfileSettingKey get setting;
  AiPromptProfile get profile;

  /// Ο τίτλος και η περιγραφή του διαλόγου επεξεργασίας.
  String get title;
  String get description;
}

extension PersonalAiPromptStore on PersonalAiPrompt {
  /// Η προτροπή που ισχύει για τον χρήστη: η δική του, αλλιώς η εργοστασιακή.
  Future<String> read() async {
    final raw = (await ScopedSettings.getString(setting))?.trim() ?? '';
    return raw.isEmpty ? profile.defaultTemplate : raw;
  }

  /// Κενό κείμενο σημαίνει «πίσω στην εργοστασιακή».
  Future<void> write(String text) async {
    final normalized = text.trim();
    await ScopedSettings.setString(
      setting,
      normalized.isEmpty ? profile.defaultTemplate : normalized,
    );
  }
}
