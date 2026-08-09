import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/elapsed_stopwatch_format.dart';
import 'build_output_log.dart';
import 'publish_reminder_provider.dart';
import 'release_publisher_service.dart';

/// Τελικό αποτέλεσμα μιας εκτέλεσης δημοσίευσης, έτοιμο για προβολή.
class ReleasePublishCompletion {
  const ReleasePublishCompletion({
    required this.result,
    required this.elapsedLabel,
    required this.statusMessage,
  });

  final ReleasePublishResult result;

  /// Συνολικός χρόνος της εκτέλεσης, μορφοποιημένος.
  final String elapsedLabel;

  /// Πλήρες μήνυμα κατάστασης για την κάρτα και το snackbar.
  final String statusMessage;

  bool get isFailure => result.status == ReleasePublishStatus.failure;
}

/// Κατάσταση της (το πολύ μίας) εκτέλεσης δημοσίευσης.
class ReleasePublishRunState {
  const ReleasePublishRunState({required this.running, this.completion});

  static const idle = ReleasePublishRunState(running: false);

  final bool running;

  /// Το φινάλε της πιο πρόσφατης εκτέλεσης· null πριν από την πρώτη.
  final ReleasePublishCompletion? completion;
}

/// Η εκτέλεση δημοσίευσης ζει εδώ — με ζωή εφαρμογής, όχι οθόνης.
///
/// Συμβόλαιο: **μία το πολύ εκτέλεση κάθε στιγμή, ορατή από παντού, με φινάλε
/// που βρίσκει τον χρήστη όπου κι αν είναι.** Η κάρτα «Δημοσίευση έκδοσης»
/// είναι απλός θεατής: αν ο χρήστης φύγει από τα Σενάρια σφαλμάτων, η
/// εκτέλεση, το log και το χρονόμετρο συνεχίζουν εδώ και τον περιμένουν.
class ReleasePublishRunNotifier extends Notifier<ReleasePublishRunState> {
  /// Έξοδος μεταγλώττισης — επιβιώνει την καταστροφή της οθόνης.
  final BuildOutputLog log = BuildOutputLog();

  final Stopwatch _stopwatch = Stopwatch();

  /// Χρόνος που τρέχει η τρέχουσα (ή έτρεξε η τελευταία) εκτέλεση.
  Duration get elapsed => _stopwatch.elapsed;

  @override
  ReleasePublishRunState build() {
    ref.onDispose(log.dispose);
    return ReleasePublishRunState.idle;
  }

  /// Γραμμή προόδου με σφραγίδα χρόνου από το ρολόι της εκτέλεσης.
  void appendLog(String message) {
    log.append('[${formatElapsedWithMillis(_stopwatch.elapsed)}] $message');
  }

  /// Εκτελεί μία ενέργεια δημοσίευσης. Επιστρέφει false — χωρίς να τρέξει
  /// τίποτα — αν ήδη τρέχει άλλη: το «μία το πολύ εκτέλεση» επιβάλλεται εδώ,
  /// ώστε καμία οθόνη (φρεσκοχτισμένη ή μη) να μην μπορεί να το παρακάμψει.
  Future<bool> run(Future<ReleasePublishResult> Function() action) async {
    if (state.running) return false;
    log.clear();
    _stopwatch
      ..reset()
      ..start();
    state = const ReleasePublishRunState(running: true);

    ReleasePublishResult result;
    try {
      result = await action();
    } catch (e) {
      // Χωρίς αυτό, μια εξαίρεση θα άφηνε το running αιώνια true και τα
      // κουμπιά της κάρτας μόνιμα κλειδωμένα.
      result = ReleasePublishResult(
        status: ReleasePublishStatus.failure,
        message: '$e',
      );
    }

    _stopwatch.stop();
    final elapsedLabel = formatElapsedWithMillis(_stopwatch.elapsed);
    state = ReleasePublishRunState(
      running: false,
      completion: ReleasePublishCompletion(
        result: result,
        elapsedLabel: elapsedLabel,
        statusMessage: statusMessageFor(result, elapsedLabel),
      ),
    );

    // Το Unreleased άδειασε: η υπενθύμιση δημοσίευσης σβήνει τώρα, όχι στην
    // επόμενη εκκίνηση — ανεξάρτητα από το αν η οθόνη είναι ορατή.
    if (result.status == ReleasePublishStatus.success) {
      ref.invalidate(publishReminderProvider);
    }
    return true;
  }

  static String statusMessageFor(ReleasePublishResult result, String elapsed) {
    switch (result.status) {
      case ReleasePublishStatus.success:
        final base = result.message ?? 'Επιτυχία.';
        return '$base (συνολικός χρόνος: $elapsed)';
      case ReleasePublishStatus.emptyUnreleasedWarning:
        return result.message ?? '';
      case ReleasePublishStatus.failure:
        final step = result.failedStep ?? 'άγνωστο';
        return 'Αποτυχία στο βήμα «$step»: ${result.message ?? ''}';
    }
  }
}

final releasePublishRunProvider =
    NotifierProvider<ReleasePublishRunNotifier, ReleasePublishRunState>(
      ReleasePublishRunNotifier.new,
    );
