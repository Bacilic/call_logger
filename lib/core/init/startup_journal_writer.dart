import '../services/crash_log_service.dart';
import '../services/shutdown_trace_incident.dart';
import '../services/station_name.dart';
import 'startup_journal.dart';

/// Ο παραλήπτης του [StartupJournal] στον δίσκο.
///
/// Τα ίδια βήματα που κυλούν στην οθόνη εκκίνησης καταλήγουν και στο ημερήσιο
/// αρχείο συνεδριών, δίπλα στα αρχεία σφαλμάτων — ώστε το «γιατί άργησε
/// σήμερα;» να έχει απάντηση και την επόμενη μέρα.
///
/// **Γράφει βήμα-βήμα, όχι στο τέλος.** Αν η εκκίνηση πεθάνει στη μέση, το
/// αρχείο δείχνει ως πού έφτασε· μια εγγραφή «στο τέλος» δεν θα υπήρχε καν.
///
/// **Γράφει μόνο κλειστά βήματα.** Το ημερολόγιο ειδοποιεί σε κάθε αλλαγή,
/// και μια αντίστροφη μέτρηση αλλάζει το κείμενο του ίδιου βήματος δεκάδες
/// φορές· θα γέμιζε το αρχείο με το ίδιο βήμα ξανά και ξανά.
class StartupJournalWriter {
  StartupJournalWriter({
    required this.append,
    required this.appVersion,
    StartupJournal? journal,
    DateTime Function()? now,
  }) : _journal = journal ?? StartupJournal.instance,
       _now = now ?? DateTime.now;

  /// Πού καταλήγει το κείμενο. Στην εφαρμογή είναι το ημερήσιο αρχείο
  /// συνεδριών του [CrashLogService]· στα τεστ, μια μνήμη.
  final void Function(String text) append;

  final String appVersion;
  final StartupJournal _journal;
  final DateTime Function() _now;

  static StartupJournalWriter? _instance;

  static StartupJournalWriter? get instanceOrNull => _instance;

  int _writtenCount = 0;
  int _totalMs = 0;
  bool _attached = false;
  bool _sealedOnce = false;

  /// Μέγιστο μήκος λεπτομέρειας σφάλματος στη γραμμή του βήματος.
  ///
  /// Η πλήρης αιτία, με τη στοίβα της, είναι ήδη στο ημερολόγιο σφαλμάτων
  /// μέσω των σημειώσεων εκκίνησης. Εδώ χρειάζεται μόνο όσο αρκεί για να
  /// αναγνωρίσει κανείς τι ήταν — αλλιώς μια φθαρμένη βάση με εκατοντάδες
  /// γραμμές διαγνωστικών πνίγει τη γραμμή χρόνου της εκκίνησης.
  static const int _maxDetailLength = 500;

  /// Στήνει τον γραφέα της εφαρμογής και τον συνδέει στο ημερολόγιο.
  ///
  /// Καλείται μόλις γίνει γνωστός ο φάκελος των αρχείων — δηλαδή αφού ανοίξει
  /// το ημερολόγιο σφαλμάτων. Όσα βήματα προηγήθηκαν γράφονται αναδρομικά:
  /// υπάρχουν ήδη ολόκληρα στη μνήμη, απλώς δεν είχαν πού να πάνε.
  static void startForApp() {
    final service = CrashLogService.instanceOrNull;
    if (service == null) return;
    _instance?.detach();
    _instance = StartupJournalWriter(
      append: service.appendSessionText,
      appVersion: service.appVersion,
    )..attach();
  }

  /// Ξηλώνει τον γραφέα της εφαρμογής (απομόνωση τεστ).
  static void disposeForApp() {
    _instance?.detach();
    _instance = null;
  }

  void attach() {
    if (_attached) return;
    _attached = true;
    // Ο σταθμός στην κεφαλίδα: όταν η βάση είναι κοινόχρηστη, το αρχείο της
    // ημέρας δέχεται τις εκκινήσεις όλων των υπολογιστών, και χωρίς αυτόν οι
    // δύο γραμμές χρόνου μπλέκονται σε μία δυσανάγνωστη.
    final station = StationName.current;
    final who = station.isEmpty ? '' : ' · $station';
    append('${_stamp()} ══ ΕΚΚΙΝΗΣΗ v$appVersion$who ══\n');
    _journal.steps.addListener(_onStepsChanged);
    _onStepsChanged();
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _journal.steps.removeListener(_onStepsChanged);
  }

  /// Δηλώνει νέα προσπάθεια αρχικοποίησης.
  ///
  /// Το ημερολόγιο γυρίζει πίσω στο προοίμιο σε κάθε «Επανάληψη», αλλά το
  /// αρχείο δεν γυρίζει: χωρίς αυτή τη γραμμή τα ίδια βήματα θα φαίνονταν
  /// γραμμένα δύο και τρεις φορές, σαν να έγιναν πράγματι τόσες.
  void beginAttempt() {
    if (!_attached) return;
    if (_sealedOnce) {
      append('${_stamp()} ── νέα προσπάθεια ──\n');
    }
    _writtenCount = _journal.steps.value.length;
    _totalMs = 0;
  }

  /// Κλείνει την προσπάθεια: γράφει ό,τι έμεινε ανοιχτό και το αποτέλεσμα.
  void sealAttempt({required bool success}) {
    if (!_attached) return;
    _flushClosedSteps();
    _flushUnfinishedSteps();
    final total = ShutdownTraceIncident.formatDuration(_totalMs);
    append(
      success
          ? '${_stamp()} ══ ΕΤΟΙΜΗ — σύνολο βημάτων $total ══\n\n'
          : '${_stamp()} ══ Η ΕΚΚΙΝΗΣΗ ΔΕΝ ΟΛΟΚΛΗΡΩΘΗΚΕ — '
                'σύνολο βημάτων $total ══\n\n',
    );
    _sealedOnce = true;
  }

  void _onStepsChanged() => _flushClosedSteps();

  /// Προχωρά όσο το επόμενο αγραφο βήμα έχει κλείσει.
  ///
  /// Σταματά στο πρώτο που τρέχει ακόμη: η σειρά του αρχείου είναι η σειρά
  /// που συνέβησαν τα βήματα, και η εκκίνηση τα εκτελεί ένα-ένα.
  void _flushClosedSteps() {
    final steps = _journal.steps.value;
    while (_writtenCount < steps.length) {
      final step = steps[_writtenCount];
      if (step.status == StartupStepStatus.running) return;
      append(_formatStep(step));
      _totalMs += step.duration?.inMilliseconds ?? 0;
      _writtenCount++;
    }
  }

  /// Βήμα που δεν έκλεισε ποτέ. Γράφεται ρητά ως ημιτελές: η παράλειψη είναι
  /// ορατή, όχι σιωπηλή — ακριβώς όπως και στην οθόνη.
  void _flushUnfinishedSteps() {
    final steps = _journal.steps.value;
    while (_writtenCount < steps.length) {
      append(_formatStep(steps[_writtenCount], unfinished: true));
      _writtenCount++;
    }
  }

  String _formatStep(StartupStep step, {bool unfinished = false}) {
    final marker = unfinished ? 'ΗΜΙΤΕΛΕΣ' : _markerFor(step.status);
    final duration = step.duration;
    final durationPart = duration == null
        ? ''
        : ShutdownTraceIncident.formatDuration(duration.inMilliseconds);
    final buffer = StringBuffer()
      ..write(_stamp())
      ..write(' ')
      ..write(marker.padRight(12))
      // Μακριά ετικέτα (π.χ. με το κόστος του στιγμιότυπου) δεν κολλά στη
      // διάρκεια: «…κλείδωμα 1,3 δευτ.2,2 δευτ.» διαβαζόταν σαν ένας αριθμός.
      ..write(
        step.label.length >= 46 ? '${step.label} ' : step.label.padRight(46),
      )
      ..write(durationPart)
      ..writeln();
    final detail = _flatten(step.detail);
    if (detail != null) buffer.writeln('${' ' * 35}↳ $detail');
    return buffer.toString();
  }

  static String _markerFor(StartupStepStatus status) => switch (status) {
    StartupStepStatus.ok => 'ΕΝΤΑΞΕΙ',
    StartupStepStatus.skipped => 'ΠΑΡΑΛΕΙΨΗ',
    StartupStepStatus.warning => 'ΠΡΟΕΙΔΟΠ.',
    StartupStepStatus.failed => 'ΑΠΟΤΥΧΙΑ',
    StartupStepStatus.running => 'ΤΡΕΧΕΙ',
  };

  static String? _flatten(String? detail) {
    if (detail == null) return null;
    final single = detail.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.isEmpty) return null;
    if (single.length <= _maxDetailLength) return single;
    return '${single.substring(0, _maxDetailLength)}…';
  }

  String _stamp() {
    final now = _now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '[${now.year.toString().padLeft(4, '0')}-'
        '${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}]';
  }
}
