import 'dart:async';

import 'package:flutter/foundation.dart';
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
    // Ο φρουρός ξεκινά **μόνος του**, χωρίς να το θυμάται η κάθε οθόνη.
    //
    // Τρεις οθόνες κρίνουν από την κατάστασή του (Αναφορά, Ρυθμίσεις, Αίτημα
    // από εκκρεμότητα) και μόνο μία τον πυροδοτούσε — οι άλλες δύο έμεναν για
    // πάντα στο «ελέγχω» με το κουμπί αποστολής κλειδωμένο και χωρίς εξήγηση.
    // Εδώ, όποιος τον ζητήσει παίρνει απάντηση.
    //
    // Σε microtask και όχι εδώ: η `check` γράφει κατάσταση, και γραφή μέσα στο
    // ίδιο το `build` του notifier ρίχνει την οθόνη.
    Future<void>.microtask(() {
      if (!ref.mounted) return;
      unawaited(ensureCheck());
    });
    return const LansweeperConnectionChecking();
  }

  /// Εκκινεί έλεγχο αν δεν έχει ολοκληρωθεί ήδη επιτυχώς/αποτυχώς.
  Future<void> ensureCheck() => check(force: false);

  /// Δηλώνει τη σύνδεση διαθέσιμη από **απόδειξη αλλού**.
  ///
  /// Ο «Έλεγχος πράκτορα API» μιλά στο ίδιο το Lansweeper και δημιουργεί
  /// πραγματικό αίτημα — απόδειξη ισχυρότερη από κάθε ping. Χωρίς αυτό, ο
  /// χρήστης έβλεπε πράσινο «ο πράκτορας αναγνωρίστηκε» και από κάτω
  /// «Έλεγχος σύνδεσης…» που δεν τελείωνε ποτέ.
  ///
  /// Ακυρώνει και τον έλεγχο που τρέχει: ένα ping που θα απαντούσε αργότερα
  /// δεν επιτρέπεται να σβήσει απόδειξη που ήρθε πιο μπροστά.
  void markAvailable() {
    if (!ref.mounted) return;
    _checkGeneration++;
    state = const LansweeperConnectionAvailable();
  }

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
    final apiKey = ref.read(lansweeperApiKeyProvider);
    final agentUsername = ref.read(lansweeperAgentUsernameProvider);

    if (!ref.mounted || generation != _checkGeneration) return;
    state = const LansweeperConnectionChecking();

    final next = await runProbe(
      apiUrl: apiUrl,
      ticketFormUrl: ticketFormUrl,
      apiKey: apiKey,
      agentUsername: agentUsername,
    );
    if (generation != _checkGeneration || !ref.mounted) return;
    state = next;
  }

  /// Το ένα σημείο που μιλά στο δίκτυο — παρακάμψιμο στα τεστ.
  ///
  /// Χωρίς αυτό, κάθε έλεγχος της συμπεριφοράς του φρουρού θα ζητούσε αληθινό
  /// διακομιστή, δηλαδή δεν θα γραφόταν ποτέ.
  @visibleForTesting
  Future<LansweeperConnectionStatus> runProbe({
    required String apiUrl,
    required String ticketFormUrl,
    required String apiKey,
    required String agentUsername,
  }) => _runProbe(
    apiUrl: apiUrl,
    ticketFormUrl: ticketFormUrl,
    apiKey: apiKey,
    agentUsername: agentUsername,
  );

  /// Εσωτερικός έλεγχος προσβασιμότητας URL (HTTP ping) — όχι διαπιστευτήρια.
  static Future<LansweeperConnectionStatus> _runProbe({
    required String apiUrl,
    required String ticketFormUrl,
    required String apiKey,
    required String agentUsername,
  }) async {
    final reachabilityUrl = _pickReachabilityUrl(
      apiUrl: apiUrl,
      ticketFormUrl: ticketFormUrl,
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
  }) {
    if (LansweeperUrlRules.isApiEndpointUrl(apiUrl)) {
      return apiUrl.trim();
    }
    if (LansweeperUrlRules.isBrowserLaunchableUrl(ticketFormUrl)) {
      return ticketFormUrl.trim();
    }
    return null;
  }
}

final lansweeperConnectionProbeProvider =
    NotifierProvider.autoDispose<
      LansweeperConnectionProbeNotifier,
      LansweeperConnectionStatus
    >(LansweeperConnectionProbeNotifier.new);
