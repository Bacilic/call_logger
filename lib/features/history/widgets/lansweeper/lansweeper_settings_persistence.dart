import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/gemini_settings_provider.dart';
import '../../providers/lansweeper_settings_provider.dart';

class LansweeperSettingsValues {
  const LansweeperSettingsValues({
    required this.apiUrl,
    required this.ticketFormUrl,
    required this.ticketViewUrl,
    required this.apiKey,
    required this.agentUsername,
    required this.loginUrl,
    required this.helpdeskUsername,
    required this.helpdeskPassword,
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
  final String loginUrl;
  final String helpdeskUsername;
  final String helpdeskPassword;
  final String geminiApiKey;
  final String geminiPromptTemplate;
  final String geminiEndpoint;
  final String geminiPrimaryModel;
  final String geminiFallbackModel;
}

void persistLansweeperSettings(WidgetRef ref, LansweeperSettingsValues v) {
  unawaited(ref.read(lansweeperApiUrlProvider.notifier).setApiUrl(v.apiUrl));
  unawaited(
    ref
        .read(lansweeperTicketFormUrlProvider.notifier)
        .setTicketFormUrl(v.ticketFormUrl),
  );
  unawaited(
    ref
        .read(lansweeperTicketViewUrlProvider.notifier)
        .setTicketViewUrl(v.ticketViewUrl),
  );
  unawaited(ref.read(lansweeperApiKeyProvider.notifier).setApiKey(v.apiKey));
  unawaited(
    ref
        .read(lansweeperAgentUsernameProvider.notifier)
        .setAgentUsername(v.agentUsername),
  );
  unawaited(
    ref
        .read(lansweeperHelpdeskLoginUrlProvider.notifier)
        .setLoginUrl(v.loginUrl),
  );
  unawaited(
    ref
        .read(lansweeperHelpdeskWebUsernameProvider.notifier)
        .setUsername(v.helpdeskUsername),
  );
  unawaited(
    ref
        .read(lansweeperHelpdeskWebPasswordProvider.notifier)
        .setPassword(v.helpdeskPassword),
  );
  unawaited(ref.read(geminiApiKeyProvider.notifier).setApiKey(v.geminiApiKey));
  unawaited(
    ref
        .read(geminiPromptTemplateProvider.notifier)
        .setPromptTemplate(v.geminiPromptTemplate),
  );
  unawaited(
    ref.read(geminiEndpointProvider.notifier).setEndpoint(v.geminiEndpoint),
  );
  unawaited(
    ref
        .read(geminiPrimaryModelProvider.notifier)
        .setPrimaryModel(v.geminiPrimaryModel),
  );
  unawaited(
    ref
        .read(geminiFallbackModelProvider.notifier)
        .setFallbackModel(v.geminiFallbackModel),
  );
}
