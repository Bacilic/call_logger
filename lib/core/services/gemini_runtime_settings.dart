import '../database/database_helper.dart';
import '../database/settings_repository.dart';
import 'app_settings_bool.dart';
import 'gemini_api_key_resolution.dart';
import 'gemini_ticket_service.dart';

/// Ρυθμίσεις Gemini για on-demand κλήσεις (ανεξάρτητα από autoDispose providers).
class GeminiRuntimeSettings {
  const GeminiRuntimeSettings({
    required this.apiKey,
    required this.endpoint,
    required this.primaryModel,
    required this.fallbackEnabled,
    required this.fallbackModel,
  });

  final String apiKey;
  final String endpoint;
  final String primaryModel;

  /// Αν η εφεδρεία είναι ενεργή. **Η ρύθμιση είναι μία για όλη την εφαρμογή:**
  /// το ίδιο εφεδρικό μοντέλο εξυπηρετεί κάθε κλήση προς την ΤΝ, ώστε ο χρήστης
  /// να μη συμπληρώνει την ίδια απόφαση σε δύο οθόνες.
  final bool fallbackEnabled;
  final String fallbackModel;

  /// Τα μοντέλα προς δοκιμή, με τη φυσιολογική σειρά και χωρίς διπλοεγγραφές.
  ///
  /// Η **σειρά υγείας** δεν αποφασίζεται εδώ: αυτή είναι η προτίμηση του
  /// χρήστη, και τη μνήμη του υπολογιστή την επιβάλλει όποιος εκτελεί την
  /// αλυσίδα.
  List<String> get candidateModels {
    final primary = primaryModel.trim();
    final fallback = fallbackModel.trim();
    return <String>[
      if (primary.isNotEmpty) primary,
      if (fallbackEnabled && fallback.isNotEmpty && fallback != primary)
        fallback,
    ];
  }

  static Future<GeminiRuntimeSettings> loadFromDatabase() async {
    final db = await DatabaseHelper.instance.database;
    final repo = SettingsRepository(db);

    // Η ΙΔΙΑ αλυσίδα με την οθόνη: προσωπικό κλειδί αν υπάρχει, αλλιώς κοινό.
    final apiKey = await resolveGeminiApiKey();

    final endpointRaw =
        (await repo.getSetting(kGeminiEndpointSettingKey))?.trim() ?? '';
    final endpoint = GeminiTicketService.normalizeEndpointTemplate(
      endpointRaw.isEmpty ? kDefaultGeminiEndpoint : endpointRaw,
    );

    var primaryModel =
        (await repo.getSetting(kGeminiPrimaryModelSettingKey))?.trim() ?? '';
    if (primaryModel.isEmpty) {
      final legacyEndpoint = endpointRaw.isNotEmpty
          ? GeminiTicketService.normalizeEndpointTemplate(endpointRaw)
          : '';
      primaryModel =
          GeminiTicketService.modelFromEndpoint(legacyEndpoint) ??
          kDefaultGeminiPrimaryModel;
    }
    if (primaryModel.isEmpty) {
      primaryModel = kDefaultGeminiPrimaryModel;
    }

    // Η ΙΔΙΑ ανάγνωση με την οθόνη Lansweeper: απουσία ρύθμισης σημαίνει
    // «ενεργή εφεδρεία», ώστε μια εγκατάσταση που δεν την άγγιξε ποτέ να μη
    // μένει χωρίς δεύτερη επιλογή.
    final fallbackRaw = await repo.getSetting(kGeminiFallbackEnabledSettingKey);
    final fallbackEnabled = fallbackRaw == null
        ? true
        : parseBoolAppSetting(fallbackRaw);

    var fallbackModel =
        (await repo.getSetting(kGeminiFallbackModelSettingKey))?.trim() ?? '';
    if (fallbackModel.isEmpty) {
      fallbackModel = kDefaultGeminiFallbackModel;
    }

    return GeminiRuntimeSettings(
      apiKey: apiKey,
      endpoint: endpoint,
      primaryModel: primaryModel,
      fallbackEnabled: fallbackEnabled,
      fallbackModel: fallbackModel,
    );
  }
}
