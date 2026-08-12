import 'package:flutter/foundation.dart';

/// Έκβαση ενός βήματος εκκίνησης.
enum StartupStepStatus {
  /// Τρέχει αυτή τη στιγμή.
  running,

  /// Ολοκληρώθηκε κανονικά.
  ok,

  /// Δεν είχε δουλειά να κάνει — δεν εμφανίζεται στην οθόνη.
  skipped,

  /// Απέτυχε, αλλά η εκκίνηση συνεχίζεται.
  warning,

  /// Απέτυχε και σταματά την εκκίνηση.
  failed,
}

/// Ένα βήμα της εκκίνησης, όπως το βλέπει ο χρήστης.
@immutable
class StartupStep {
  const StartupStep({
    required this.label,
    required this.status,
    this.duration,
    this.detail,
  });

  final String label;
  final StartupStepStatus status;

  /// Πόσο κράτησε· `null` όσο τρέχει.
  final Duration? duration;

  /// Επιπλέον πληροφορία για προειδοποιήσεις και αποτυχίες.
  final String? detail;

  StartupStep copyWith({
    String? label,
    StartupStepStatus? status,
    Duration? duration,
    String? detail,
  }) {
    return StartupStep(
      label: label ?? this.label,
      status: status ?? this.status,
      duration: duration ?? this.duration,
      detail: detail ?? this.detail,
    );
  }

  @override
  String toString() => 'StartupStep($label, $status)';
}

/// Λαβή σε βήμα που τρέχει. Ο καλών κλείνει το βήμα με μία από τις μεθόδους
/// έκβασης· αν το ξεχάσει, το βήμα μένει «running» και φαίνεται στην οθόνη —
/// η παράλειψη είναι ορατή, όχι σιωπηλή.
class StartupStepHandle {
  StartupStepHandle._(this._journal, this._index) : _watch = Stopwatch()..start();

  final StartupJournal _journal;
  final int _index;
  final Stopwatch _watch;
  bool _closed = false;

  /// Αλλάζει το κείμενο χωρίς να κλείσει το βήμα (π.χ. αντίστροφη μέτρηση).
  void relabel(String label) {
    if (_closed) return;
    _journal._update(_index, (s) => s.copyWith(label: label));
  }

  void ok([String? label]) => _close(StartupStepStatus.ok, label, null);

  void skip([String? label]) => _close(StartupStepStatus.skipped, label, null);

  void warn(String detail, [String? label]) =>
      _close(StartupStepStatus.warning, label, detail);

  void fail(String detail, [String? label]) =>
      _close(StartupStepStatus.failed, label, detail);

  void _close(StartupStepStatus status, String? label, String? detail) {
    if (_closed) return;
    _closed = true;
    _watch.stop();
    _journal._update(
      _index,
      (s) => s.copyWith(
        label: label ?? s.label,
        status: status,
        duration: _watch.elapsed,
        detail: detail,
      ),
    );
  }
}

/// Το ημερολόγιο της εκκίνησης: κάθε βήμα από την πρώτη γραμμή του `main()`
/// μέχρι το άνοιγμα του κελύφους, με όνομα, έκβαση και διάρκεια.
///
/// Δεν είναι provider επίτηδες. Τα μισά βήματα τρέχουν πριν υπάρξει
/// `ProviderScope` — ένας απλός [ValueNotifier] είναι το μόνο που δουλεύει
/// και στις δύο πλευρές αυτής της γραμμής.
class StartupJournal {
  StartupJournal._();

  static final StartupJournal instance = StartupJournal._();

  final ValueNotifier<List<StartupStep>> steps =
      ValueNotifier<List<StartupStep>>(const <StartupStep>[]);

  /// Ξεκινά βήμα και επιστρέφει τη λαβή του.
  StartupStepHandle begin(String label) {
    final next = List<StartupStep>.of(steps.value)
      ..add(
        StartupStep(label: label, status: StartupStepStatus.running),
      );
    steps.value = next;
    return StartupStepHandle._(this, next.length - 1);
  }

  /// Καταγράφει βήμα που έχει ήδη τελειώσει (χωρίς μετρήσιμη διάρκεια).
  void note(
    String label, {
    StartupStepStatus status = StartupStepStatus.ok,
    String? detail,
  }) {
    steps.value = List<StartupStep>.of(steps.value)
      ..add(StartupStep(label: label, status: status, detail: detail));
  }

  /// Τρέχει το [action] ως βήμα, κλείνοντάς το σωστά ό,τι κι αν συμβεί.
  ///
  /// Η αποτυχία γίνεται προειδοποίηση και **δεν** ξαναπετιέται: τα βήματα που
  /// περνούν από εδώ είναι νοικοκυριό, όχι προϋποθέσεις. Όποιο βήμα οφείλει να
  /// ρίξει την εκκίνηση το δηλώνει μόνο του με [StartupStepHandle.fail].
  Future<T?> runStep<T>(String label, Future<T> Function() action) async {
    final step = begin(label);
    try {
      final result = await action();
      step.ok();
      return result;
    } catch (e) {
      step.warn(e.toString());
      return null;
    }
  }

  /// Τα βήματα που αξίζει να δει ο χρήστης — όσα είχαν πράγματι δουλειά.
  List<StartupStep> get visibleSteps => steps.value
      .where((s) => s.status != StartupStepStatus.skipped)
      .toList(growable: false);

  /// True μόλις κάποιο βήμα κηρύξει αποτυχία.
  bool get hasFailure =>
      steps.value.any((s) => s.status == StartupStepStatus.failed);

  /// Πόσα βήματα ανήκουν στο προοίμιο — δες [sealBootPrefix].
  int _bootPrefixLength = 0;

  /// Μηδενίζει τα πάντα, προοίμιο μαζί. Για απομόνωση τεστ.
  void reset() {
    steps.value = const <StartupStep>[];
    _bootPrefixLength = 0;
  }

  /// Σφραγίζει όσα βήματα γράφτηκαν ως τώρα ως «προοίμιο εκκίνησης»: ό,τι
  /// έγινε πριν υπάρξει διεπαφή — ορίσματα, προφίλ, μηχανή, παράθυρο — και
  /// δεν ξανατρέχει ποτέ, ούτε στην επαναδοκιμή.
  void sealBootPrefix() {
    _bootPrefixLength = steps.value.length;
  }

  /// Γυρίζει το ημερολόγιο στο σφραγισμένο προοίμιο.
  ///
  /// Κάθε νέα προσπάθεια αρχικοποίησης (επαναδοκιμή, εναλλαγή βάσης) ξεκινά
  /// από εδώ. Χωρίς αυτό, το τρίτο πάτημα του «Επανάληψη» θα έδειχνε τα βήματα
  /// τρεις φορές· με σκέτο [reset] θα έσβηνε και το προοίμιο, που δεν πρόκειται
  /// να ξαναγραφτεί.
  void rewindToBootPrefix() {
    final current = steps.value;
    if (current.length <= _bootPrefixLength) return;
    steps.value = current.sublist(0, _bootPrefixLength);
  }

  void _update(int index, StartupStep Function(StartupStep) transform) {
    final current = steps.value;
    if (index < 0 || index >= current.length) return;
    final next = List<StartupStep>.of(current);
    next[index] = transform(next[index]);
    steps.value = next;
  }
}
