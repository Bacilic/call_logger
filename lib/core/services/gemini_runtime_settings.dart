import '../database/database_helper.dart';
import '../database/settings_repository.dart';
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

    final apiKey =
        (await repo.getSetting(kGeminiApiKeySettingKey))?.trim() ?? '';

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
      primaryModel = GeminiTicketService.modelFromEndpoint(legacyEndpoint) ??
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
