import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/lansweeper_agent_api_probe.dart';
import '../../../core/services/lansweeper_host_reachability.dart';
import '../models/lansweeper_connection_status.dart';
import '../widgets/lansweeper/lansweeper_url_rules.dart';
import 'lansweeper_settings_provider.dart';

class LansweeperConnectionProbeNotifier
    extends Notifier<LansweeperConnectionStatus> {
  int _checkGeneration = 0;

  @override
  LansweeperConnectionStatus build() {
    ref.onDispose(() {
      _checkGeneration++;
    });
    return const LansweeperConnectionChecking();
  }

  /// Εκκινεί έλεγχο αν δεν έχει ολοκληρωθεί ήδη επιτυχώς/αποτυχώς.
  Future<void> ensureCheck() => check(force: false);

  /// Εκτελεί (ή επαναλαμβάνει) τον έλεγχο σύνδεσης.
  Future<void> check({bool force = true}) async {
    if (!ref.mounted) return;

    final current = state;
    if (!force &&
        (current is LansweeperConnectionAvailable ||
            current is LansweeperConnectionUnavailable)) {
      return;
    }

    final generation = ++_checkGeneration;

    final apiUrl = ref.read(lansweeperApiUrlProvider);
    final ticketFormUrl = ref.read(lansweeperTicketFormUrlProvider);
    final loginUrl = ref.read(lansweeperHelpdeskLoginUrlProvider);
    final apiKey = ref.read(lansweeperApiKeyProvider);
    final agentUsername = ref.read(lansweeperAgentUsernameProvider);

    if (!ref.mounted || generation != _checkGeneration) return;
    state = const LansweeperConnectionChecking();

    final next = await _runProbe(
      apiUrl: apiUrl,
      ticketFormUrl: ticketFormUrl,
      loginUrl: loginUrl,
      apiKey: apiKey,
      agentUsername: agentUsername,
    );
    if (generation != _checkGeneration || !ref.mounted) return;
    state = next;
  }

  /// Εσωτερικός έλεγχος προσβασιμότητας URL (HTTP ping) — όχι διαπιστευτήρια.
  static Future<LansweeperConnectionStatus> _runProbe({
    required String apiUrl,
    required String ticketFormUrl,
    required String loginUrl,
    required String apiKey,
    required String agentUsername,
  }) async {
    final reachabilityUrl = _pickReachabilityUrl(
      apiUrl: apiUrl,
      ticketFormUrl: ticketFormUrl,
      loginUrl: loginUrl,
    );

    if (reachabilityUrl == null) {
      final fallback = await LansweeperAgentApiProbe.verify(
        apiUrl: apiUrl,
        apiKey: apiKey,
        agentUsername: agentUsername,
      );
      return LansweeperConnectionUnavailable(fallback.message);
    }

    final ping = await LansweeperHostReachability.check(reachabilityUrl);
    if (ping.reachable) {
      return const LansweeperConnectionAvailable();
    }
    return LansweeperConnectionUnavailable(ping.message);
  }

  static String? _pickReachabilityUrl({
    required String apiUrl,
    required String ticketFormUrl,
    required String loginUrl,
  }) {
    if (LansweeperUrlRules.isApiEndpointUrl(apiUrl)) {
      return apiUrl.trim();
    }
    if (LansweeperUrlRules.isBrowserLaunchableUrl(ticketFormUrl)) {
      return ticketFormUrl.trim();
    }
    if (LansweeperUrlRules.isBrowserLaunchableUrl(loginUrl)) {
      return loginUrl.trim();
    }
    return null;
  }
}

final lansweeperConnectionProbeProvider =
    NotifierProvider.autoDispose<LansweeperConnectionProbeNotifier,
        LansweeperConnectionStatus>(
  LansweeperConnectionProbeNotifier.new,
);
