import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/database_persistence_error_snackbar.dart';
import '../../providers/gemini_settings_provider.dart';
import '../../providers/lansweeper_settings_provider.dart';

class LansweeperSettingsValues {
  const LansweeperSettingsValues({
    required this.apiUrl,
    required this.ticketFormUrl,
    required this.ticketViewUrl,
    required this.apiKey,
    required this.agentUsername,
    required this.geminiApiKey,
    required this.geminiPromptTemplate,
    required this.geminiEndpoint,
    required this.geminiPrimaryModel,
    required this.geminiFallbackModel,
  });

  final String apiUrl;
  final String ticketFormUrl;
  final String ticketViewUrl;
  final String apiKey;
  final String agentUsername;
  final String geminiApiKey;
  final String geminiPromptTemplate;
  final String geminiEndpoint;
  final String geminiPrimaryModel;
  final String geminiFallbackModel;
}

/// Αποθηκεύει τις ρυθμίσεις σύνδεσης χωρίς να μπλοκάρει τη φόρμα.
///
/// Το [context] δεν είναι διακοσμητικό: δέκα εγγραφές έφευγαν «και ξέχνα το»,
/// οπότε μια άφταστη κοινόχρηστη βάση τις κατάπινε όλες σιωπηλά.
void persistLansweeperSettings(
  BuildContext context,
  WidgetRef ref,
  LansweeperSettingsValues v,
) {
  persistSettingInBackground(context, ref.read(lansweeperApiUrlProvider.notifier).setApiUrl(v.apiUrl));
  persistSettingInBackground(
    context,
    ref
        .read(lansweeperTicketFormUrlProvider.notifier)
        .setTicketFormUrl(v.ticketFormUrl),
  );
  persistSettingInBackground(
    context,
    ref
        .read(lansweeperTicketViewUrlProvider.notifier)
        .setTicketViewUrl(v.ticketViewUrl),
  );
  persistSettingInBackground(context, ref.read(lansweeperApiKeyProvider.notifier).setApiKey(v.apiKey));
  persistSettingInBackground(
    context,
    ref
        .read(lansweeperAgentUsernameProvider.notifier)
        .setAgentUsername(v.agentUsername),
  );
  persistSettingInBackground(context, ref.read(geminiApiKeyProvider.notifier).setApiKey(v.geminiApiKey));
  persistSettingInBackground(
    context,
    ref
        .read(geminiPromptTemplateProvider.notifier)
        .setPromptTemplate(v.geminiPromptTemplate),
  );
  persistSettingInBackground(
    context,
    ref.read(geminiEndpointProvider.notifier).setEndpoint(v.geminiEndpoint),
  );
  persistSettingInBackground(
    context,
    ref
        .read(geminiPrimaryModelProvider.notifier)
        .setPrimaryModel(v.geminiPrimaryModel),
  );
  persistSettingInBackground(
    context,
    ref
        .read(geminiFallbackModelProvider.notifier)
        .setFallbackModel(v.geminiFallbackModel),
  );
}
