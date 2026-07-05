// Κοινά test doubles για widget τεστ διάλογου αναφοράς Lansweeper.
//
// Χρησιμοποιούνται από lansweeper_report_dialog_characterization_test.dart,
// lansweeper_report_multi_immediate_submit_test.dart, lansweeper_sync_invalidates_history_test.dart.

import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:call_logger/features/history/models/dashboard_date_preset.dart';
import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:call_logger/features/history/models/lansweeper_connection_status.dart';
import 'package:call_logger/features/history/providers/dashboard_provider.dart';
import 'package:call_logger/features/history/providers/gemini_settings_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_connection_probe_provider.dart';
import 'package:call_logger/features/history/providers/lansweeper_settings_provider.dart';

const kTestLansweeperApiUrl = 'https://test.example.com/api.aspx';

class AlwaysAvailableLansweeperConnectionProbe
    extends LansweeperConnectionProbeNotifier {
  @override
  LansweeperConnectionStatus build() => const LansweeperConnectionAvailable();

  @override
  Future<void> ensureCheck() async {}

  @override
  Future<void> check({bool force = true}) async {
    state = const LansweeperConnectionAvailable();
  }
}

class AllDatesDashboardFilterNotifier extends DashboardFilterNotifier {
  @override
  DashboardFilterModel build() {
    return DashboardDatePreset.applyToFilter(
      const DashboardFilterModel(),
      DashboardDatePreset.all,
    );
  }
}

class FixedLansweeperApiUrlNotifier extends LansweeperApiUrlNotifier {
  @override
  String build() => kTestLansweeperApiUrl;
}

class FixedLansweeperTicketFormUrlNotifier
    extends LansweeperTicketFormUrlNotifier {
  @override
  String build() => 'https://test.example.com/ticketform.aspx';
}

class FixedLansweeperTicketViewUrlNotifier
    extends LansweeperTicketViewUrlNotifier {
  @override
  String build() => 'https://test.example.com/ticket.aspx?tid={tid}';
}

class FixedLansweeperApiKeyNotifier extends LansweeperApiKeyNotifier {
  @override
  String build() => 'test-api-key';
}

class FixedLansweeperAgentUsernameNotifier
    extends LansweeperAgentUsernameNotifier {
  @override
  String build() => 'test.agent@example.com';
}

class FixedGeminiApiKeyNotifier extends GeminiApiKeyNotifier {
  @override
  String build() => '';
}

class FixedGeminiPromptTemplateNotifier extends GeminiPromptTemplateNotifier {
  @override
  String build() => kDefaultAiPromptTemplate;
}

class FixedGeminiEndpointNotifier extends GeminiEndpointNotifier {
  @override
  String build() => kDefaultGeminiEndpoint;
}

class FixedGeminiPrimaryModelNotifier extends GeminiPrimaryModelNotifier {
  @override
  String build() => '';
}

class FixedGeminiFallbackEnabledNotifier extends GeminiFallbackEnabledNotifier {
  @override
  bool build() => false;
}

class FixedGeminiFallbackModelNotifier extends GeminiFallbackModelNotifier {
  @override
  String build() => '';
}
