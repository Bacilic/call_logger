// Unit test: persistLansweeperSettings — χαρτογράφηση 13 πεδίων -> providers.
//
//   flutter test test/features/history/lansweeper_settings_persistence_test.dart

import 'package:call_logger/features/history/providers/gemini_settings_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_settings_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_settings_persistence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

const _vApiUrl = 'VAL_API_URL';
const _vTicketFormUrl = 'VAL_TICKET_FORM_URL';
const _vTicketViewUrl = 'VAL_TICKET_VIEW_URL';
const _vLansweeperApiKey = 'VAL_LANSWEEPER_API_KEY';
const _vAgentUsername = 'VAL_AGENT_USERNAME';
const _vLoginUrl = 'VAL_LOGIN_URL';
const _vHelpdeskUsername = 'VAL_HELPDESK_USERNAME';
const _vHelpdeskPassword = 'VAL_HELPDESK_PASSWORD';
const _vGeminiApiKey = 'VAL_GEMINI_API_KEY';
const _vGeminiPromptTemplate = 'VAL_GEMINI_PROMPT';
const _vGeminiEndpoint = 'VAL_GEMINI_ENDPOINT';
const _vGeminiPrimaryModel = 'VAL_GEMINI_PRIMARY';
const _vGeminiFallbackModel = 'VAL_GEMINI_FALLBACK';

const _kValues = LansweeperSettingsValues(
  apiUrl: _vApiUrl,
  ticketFormUrl: _vTicketFormUrl,
  ticketViewUrl: _vTicketViewUrl,
  apiKey: _vLansweeperApiKey,
  agentUsername: _vAgentUsername,
  loginUrl: _vLoginUrl,
  helpdeskUsername: _vHelpdeskUsername,
  helpdeskPassword: _vHelpdeskPassword,
  geminiApiKey: _vGeminiApiKey,
  geminiPromptTemplate: _vGeminiPromptTemplate,
  geminiEndpoint: _vGeminiEndpoint,
  geminiPrimaryModel: _vGeminiPrimaryModel,
  geminiFallbackModel: _vGeminiFallbackModel,
);

class RecordingLansweeperApiUrlNotifier extends LansweeperApiUrlNotifier {
  RecordingLansweeperApiUrlNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setApiUrl(String value) async {
    recorded['apiUrl'] = value;
    state = value;
  }
}

class RecordingLansweeperTicketFormUrlNotifier
    extends LansweeperTicketFormUrlNotifier {
  RecordingLansweeperTicketFormUrlNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setTicketFormUrl(String value) async {
    recorded['ticketFormUrl'] = value;
    state = value;
  }
}

class RecordingLansweeperTicketViewUrlNotifier
    extends LansweeperTicketViewUrlNotifier {
  RecordingLansweeperTicketViewUrlNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setTicketViewUrl(String value) async {
    recorded['ticketViewUrl'] = value;
    state = value;
  }
}

class RecordingLansweeperApiKeyNotifier extends LansweeperApiKeyNotifier {
  RecordingLansweeperApiKeyNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setApiKey(String value) async {
    recorded['lansweeperApiKey'] = value;
    state = value;
  }
}

class RecordingLansweeperAgentUsernameNotifier
    extends LansweeperAgentUsernameNotifier {
  RecordingLansweeperAgentUsernameNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setAgentUsername(String value) async {
    recorded['agentUsername'] = value;
    state = value;
  }
}

class RecordingLansweeperHelpdeskLoginUrlNotifier
    extends LansweeperHelpdeskLoginUrlNotifier {
  RecordingLansweeperHelpdeskLoginUrlNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setLoginUrl(String value) async {
    recorded['loginUrl'] = value;
    state = value;
  }
}

class RecordingLansweeperHelpdeskWebUsernameNotifier
    extends LansweeperHelpdeskWebUsernameNotifier {
  RecordingLansweeperHelpdeskWebUsernameNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setUsername(String value) async {
    recorded['helpdeskUsername'] = value;
    state = value;
  }
}

class RecordingLansweeperHelpdeskWebPasswordNotifier
    extends LansweeperHelpdeskWebPasswordNotifier {
  RecordingLansweeperHelpdeskWebPasswordNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setPassword(String value) async {
    recorded['helpdeskPassword'] = value;
    state = value;
  }
}

class RecordingGeminiApiKeyNotifier extends GeminiApiKeyNotifier {
  RecordingGeminiApiKeyNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setApiKey(String value) async {
    recorded['geminiApiKey'] = value;
    state = value;
  }
}

class RecordingGeminiPromptTemplateNotifier
    extends GeminiPromptTemplateNotifier {
  RecordingGeminiPromptTemplateNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setPromptTemplate(String value) async {
    recorded['geminiPromptTemplate'] = value;
    state = value;
  }
}

class RecordingGeminiEndpointNotifier extends GeminiEndpointNotifier {
  RecordingGeminiEndpointNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setEndpoint(String value) async {
    recorded['geminiEndpoint'] = value;
    state = value;
  }
}

class RecordingGeminiPrimaryModelNotifier extends GeminiPrimaryModelNotifier {
  RecordingGeminiPrimaryModelNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setPrimaryModel(String value) async {
    recorded['geminiPrimaryModel'] = value;
    state = value;
  }
}

class RecordingGeminiFallbackModelNotifier extends GeminiFallbackModelNotifier {
  RecordingGeminiFallbackModelNotifier(this.recorded);

  final Map<String, String> recorded;

  @override
  String build() => '';

  @override
  Future<void> setFallbackModel(String value) async {
    recorded['geminiFallbackModel'] = value;
    state = value;
  }
}

List<Override> _recordingOverrides(Map<String, String> recorded) {
  return <Override>[
    lansweeperApiUrlProvider.overrideWith(
      () => RecordingLansweeperApiUrlNotifier(recorded),
    ),
    lansweeperTicketFormUrlProvider.overrideWith(
      () => RecordingLansweeperTicketFormUrlNotifier(recorded),
    ),
    lansweeperTicketViewUrlProvider.overrideWith(
      () => RecordingLansweeperTicketViewUrlNotifier(recorded),
    ),
    lansweeperApiKeyProvider.overrideWith(
      () => RecordingLansweeperApiKeyNotifier(recorded),
    ),
    lansweeperAgentUsernameProvider.overrideWith(
      () => RecordingLansweeperAgentUsernameNotifier(recorded),
    ),
    lansweeperHelpdeskLoginUrlProvider.overrideWith(
      () => RecordingLansweeperHelpdeskLoginUrlNotifier(recorded),
    ),
    lansweeperHelpdeskWebUsernameProvider.overrideWith(
      () => RecordingLansweeperHelpdeskWebUsernameNotifier(recorded),
    ),
    lansweeperHelpdeskWebPasswordProvider.overrideWith(
      () => RecordingLansweeperHelpdeskWebPasswordNotifier(recorded),
    ),
    geminiApiKeyProvider.overrideWith(
      () => RecordingGeminiApiKeyNotifier(recorded),
    ),
    geminiPromptTemplateProvider.overrideWith(
      () => RecordingGeminiPromptTemplateNotifier(recorded),
    ),
    geminiEndpointProvider.overrideWith(
      () => RecordingGeminiEndpointNotifier(recorded),
    ),
    geminiPrimaryModelProvider.overrideWith(
      () => RecordingGeminiPrimaryModelNotifier(recorded),
    ),
    geminiFallbackModelProvider.overrideWith(
      () => RecordingGeminiFallbackModelNotifier(recorded),
    ),
  ];
}

void main() {
  testWidgets('persistLansweeperSettings γράφει και τα 13 πεδία στους σωστούς providers', (tester) async {
    final recorded = <String, String>{};
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: _recordingOverrides(recorded),
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    persistLansweeperSettings(capturedRef, _kValues);
    await tester.pump();

    expect(recorded['apiUrl'], _vApiUrl);
    expect(recorded['ticketFormUrl'], _vTicketFormUrl);
    expect(recorded['ticketViewUrl'], _vTicketViewUrl);
    expect(recorded['loginUrl'], _vLoginUrl);

    expect(recorded['lansweeperApiKey'], _vLansweeperApiKey);
    expect(recorded['geminiApiKey'], _vGeminiApiKey);
    expect(recorded['lansweeperApiKey'], isNot(_vGeminiApiKey));

    expect(recorded['helpdeskUsername'], _vHelpdeskUsername);
    expect(recorded['helpdeskPassword'], _vHelpdeskPassword);
    expect(recorded['helpdeskUsername'], isNot(_vHelpdeskPassword));

    expect(recorded['geminiPrimaryModel'], _vGeminiPrimaryModel);
    expect(recorded['geminiFallbackModel'], _vGeminiFallbackModel);
    expect(recorded['geminiPrimaryModel'], isNot(_vGeminiFallbackModel));

    expect(recorded['agentUsername'], _vAgentUsername);
    expect(recorded['geminiPromptTemplate'], _vGeminiPromptTemplate);
    expect(recorded['geminiEndpoint'], _vGeminiEndpoint);
    expect(recorded, hasLength(13));
  });
}
