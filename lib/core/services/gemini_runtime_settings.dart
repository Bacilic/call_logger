import '../database/database_helper.dart';
import '../database/settings_repository.dart';
import 'gemini_api_key_resolution.dart';
import 'gemini_ticket_service.dart';

/// Ρυθμίσεις Gemini για on-demand κλήσεις (ανεξάρτητα από autoDispose providers).
class GeminiRuntimeSettings {
  const GeminiRuntimeSettings({
    required this.apiKey,
    required this.endpoint,
    required this.primaryModel,
  });

  final String apiKey;
  final String endpoint;
  final String primaryModel;

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

    return GeminiRuntimeSettings(
      apiKey: apiKey,
      endpoint: endpoint,
      primaryModel: primaryModel,
    );
  }
}
