import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/remote_tool.dart';
import '../../../core/services/remote_tool_connect_wait.dart';
import '../../../core/utils/user_facing_error_messages.dart';
import 'remote_paths_provider.dart';

/// Το ρολόι του κλειδώματος, σε δικό του provider ώστε ο έλεγχος να μπορεί να
/// το καρφώσει. Μία πηγή χρόνου: ο χρονομετρητής παρακάτω είναι μετρονόμος για
/// το ξαναζωγράφισμα, τα δευτερόλεπτα βγαίνουν πάντα από εδώ.
final remoteConnectClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Μέχρι πότε είναι κλειδωμένη κάθε σύνδεση που ξεκίνησε.
///
/// **Ζει έξω από την οθόνη, σκόπιμα.** Η προηγούμενη ένδειξη «γίνεται σύνδεση»
/// ήταν πεδίο μέσα στο widget των κουμπιών — και το widget ξαναχτίζεται σε
/// κάθε αλλαγή εξοπλισμού ή εκκαθάριση της φόρμας. Το κλείδωμα θα εξαφανιζόταν
/// ακριβώς στις κινήσεις που κάνει κανείς όσο περιμένει, και το επόμενο
/// πάτημα θα άνοιγε δεύτερη συνεδρία.
///
/// Το κλειδί είναι **ζεύγος εργαλείου και στόχου**: όσο περιμένεις το RDP για
/// έναν υπολογιστή, το VNC για κάποιον άλλον μένει διαθέσιμο.
final remoteConnectCooldownProvider =
    NotifierProvider<RemoteConnectCooldownNotifier, Map<String, DateTime>>(
      RemoteConnectCooldownNotifier.new,
    );

class RemoteConnectCooldownNotifier extends Notifier<Map<String, DateTime>> {
  Timer? _ticker;

  @override
  Map<String, DateTime> build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _ticker = null;
    });
    return const {};
  }

  /// Ένα κλείδωμα ανά εργαλείο **και** στόχο.
  static String keyFor({required int toolId, required String target}) =>
      '$toolId|${target.trim().toLowerCase()}';

  DateTime _now() => ref.read(remoteConnectClockProvider)();

  /// Ξεκινά το κλείδωμα. Καλείται **μόνο** μετά από επιβεβαιωμένη εκκίνηση.
  ///
  /// Μηδενική ή αρνητική διάρκεια σημαίνει «χωρίς κλείδωμα» και δεν γράφει
  /// τίποτα: η ρύθμιση επιτρέπει ρητά το μηδέν για όποιον δεν το θέλει.
  void begin({
    required int toolId,
    required String target,
    required Duration wait,
  }) {
    if (wait <= Duration.zero) return;
    final key = keyFor(toolId: toolId, target: target);
    final next = Map<String, DateTime>.from(state)..[key] = _now().add(wait);
    state = _withoutExpired(next);
    _ensureTicking();
  }

  /// Πόσο μένει, ή [Duration.zero] όταν δεν υπάρχει ενεργό κλείδωμα.
  Duration remaining({required int toolId, required String target}) {
    final until = state[keyFor(toolId: toolId, target: target)];
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  bool isLocked({required int toolId, required String target}) =>
      remaining(toolId: toolId, target: target) > Duration.zero;

  Map<String, DateTime> _withoutExpired(Map<String, DateTime> source) {
    final now = _now();
    final kept = <String, DateTime>{};
    for (final entry in source.entries) {
      if (entry.value.isAfter(now)) kept[entry.key] = entry.value;
    }
    return kept;
  }

  /// Ο μετρονόμος τρέχει μόνο όσο υπάρχει κάτι να μετρήσει.
  void _ensureTicking() {
    if (_ticker != null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final next = _withoutExpired(state);
    if (next.length != state.length) state = next;
    if (next.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    // Το πλήθος δεν άλλαξε, αλλά τα δευτερόλεπτα ναι: νέα ταυτότητα χάρτη
    // ώστε η αντίστροφη μέτρηση να ξαναζωγραφιστεί.
    state = Map<String, DateTime>.from(next);
  }
}

/// Ποιες συνδέσεις βρίσκονται **αυτή τη στιγμή** στη φάση των ελέγχων.
///
/// Το διάστημα είναι σύντομο — όσο κρατούν οι πύλες της
/// [RemoteConnectionService] — αλλά όχι μηδενικό, και μέσα σε αυτό το κουμπί
/// πρέπει να δείχνει ότι κάτι τρέχει.
///
/// **Η εκκίνηση ζει εδώ και όχι στο widget**, ώστε μια αλλαγή εξοπλισμού ή
/// εκκαθάριση φόρμας στη μέση των ελέγχων να μη σκοτώνει τη ροή πριν προλάβει
/// να γραφτεί το κλείδωμα.
final remoteConnectLauncherProvider =
    NotifierProvider<RemoteConnectLauncherNotifier, Set<String>>(
      RemoteConnectLauncherNotifier.new,
    );

class RemoteConnectLauncherNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool isStarting({required int toolId, required String target}) =>
      state.contains(
        RemoteConnectCooldownNotifier.keyFor(toolId: toolId, target: target),
      );

  /// Ξεκινά τη σύνδεση. Επιστρέφει **μήνυμα σφάλματος**, ή `null` σε επιτυχία.
  ///
  /// Το κλείδωμα γράφεται μόνο όταν όλες οι πύλες περάσουν. Αποτυχία σημαίνει
  /// ότι το κουμπί μένει αμέσως πατήσιμο: δεν έχει νόημα να περιμένει κανείς
  /// σαράντα δευτερόλεπτα για συνεδρία που δεν ξεκίνησε ποτέ.
  Future<String?> connect({
    required RemoteTool tool,
    required String target,
    required Map<String, String> remoteParams,
    String? equipmentCode,
  }) async {
    final key = RemoteConnectCooldownNotifier.keyFor(
      toolId: tool.id,
      target: target,
    );
    final cooldown = ref.read(remoteConnectCooldownProvider.notifier);
    if (state.contains(key)) return null;
    if (cooldown.isLocked(toolId: tool.id, target: target)) return null;

    state = {...state, key};
    try {
      await ref
          .read(remoteConnectionServiceProvider)
          .launchRemoteTool(
            tool: tool,
            resolvedTarget: target,
            remoteParams: remoteParams,
            equipmentCode: equipmentCode,
          );
      cooldown.begin(
        toolId: tool.id,
        target: target,
        wait: await RemoteToolConnectWait.effectiveWait(tool),
      );
      return null;
    } catch (e) {
      return humanizeUserFacingError(e);
    } finally {
      state = {...state}..remove(key);
    }
  }
}
