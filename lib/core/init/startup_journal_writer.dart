import '../services/crash_log_service.dart';
import '../services/log_record.dart';
import '../services/shutdown_trace_incident.dart';
import 'startup_journal.dart';

/// Ο παραλήπτης του [StartupJournal] στον δίσκο.
///
/// Τα ίδια βήματα που κυλούν στην οθόνη εκκίνησης καταλήγουν και στο ημερήσιο
/// αρχείο καταγραφής, δίπλα στα σφάλματα — ώστε το «γιατί άργησε σήμερα;» να
/// έχει απάντηση και την επόμενη μέρα.
///
/// **Γράφει βήμα-βήμα, όχι στο τέλος.** Αν η εκκίνηση πεθάνει στη μέση, το
/// αρχείο δείχνει ως πού έφτασε· μια εγγραφή «στο τέλος» δεν θα υπήρχε καν.
///
/// **Γράφει μόνο κλειστά βήματα.** Το ημερολόγιο ειδοποιεί σε κάθε αλλαγή,
/// και μια αντίστροφη μέτρηση αλλάζει το κείμενο του ίδιου βήματος δεκάδες
/// φορές· θα γέμιζε το αρχείο με το ίδιο βήμα ξανά και ξανά.
///
/// Κάθε εγγραφή φέρει τη **φάση** της (`begin`, `step`, `retry`, `reinit`,
/// `end`) στα
/// δεδομένα της, ώστε όποιος διαβάζει να μετρά εκκινήσεις και να βρίσκει τον
/// χρόνο τους χωρίς να ψάχνει λέξεις στο κείμενο.
class StartupJournalWriter {
  StartupJournalWriter({
    required this.append,
    required this.appVersion,
    StartupJournal? journal,
    DateTime Function()? now,
  }) : _journal = journal ?? StartupJournal.instance,
       _now = now ?? DateTime.now;

  /// Πού καταλήγουν οι εγγραφές. Στην εφαρμογή είναι το ημερήσιο αρχείο του
  /// [CrashLogService], που τις σφραγίζει με σταθμό και έκδοση· στα τεστ, μια
  /// μνήμη.
  final void Function(LogRecord record) append;

  final String appVersion;
  final StartupJournal _journal;
  final DateTime Function() _now;

  static StartupJournalWriter? _instance;

  static StartupJournalWriter? get instanceOrNull => _instance;

  int _writtenCount = 0;
  int _totalMs = 0;
  bool _attached = false;
  bool _sealedOnce = false;
  bool _lastAttemptSucceeded = false;

  /// Μέγιστο μήκος λεπτομέρειας σφάλματος στην εγγραφή του βήματος.
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
      append: service.appendRecord,
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
    _write(
      LogSeverity.info,
      'ΕΚΚΙΝΗΣΗ v$appVersion',
      data: const {'phase': 'begin'},
    );
    _journal.steps.addListener(_onStepsChanged);
    _onStepsChanged();
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _journal.steps.removeListener(_onStepsChanged);
  }

  /// Δηλώνει νέα αρχικοποίηση.
  ///
  /// Το ημερολόγιο γυρίζει πίσω στο προοίμιο σε κάθε «Επανάληψη», αλλά το
  /// αρχείο δεν γυρίζει: χωρίς αυτή την εγγραφή τα ίδια βήματα θα φαίνονταν
  /// γραμμένα δύο και τρεις φορές, σαν να έγιναν πράγματι τόσες.
  ///
  /// **Η αιτία κρίνεται από την προηγούμενη έκβαση.** Μετά από αποτυχία, είναι
  /// νέα προσπάθεια. Μετά από επιτυχία, η εφαρμογή ήταν ήδη έτοιμη — άρα άλλαξε
  /// η βάση (αλλαγή βάσης, επαναφορά αντιγράφου, «ξεκίνα από την αρχή»). Ως
  /// «προσπάθεια» θα έκανε μια επιτυχημένη εκκίνηση να μοιάζει αποτυχημένη.
  void beginAttempt() {
    if (!_attached) return;
    if (_sealedOnce) {
      if (_lastAttemptSucceeded) {
        _write(
          LogSeverity.info,
          'νέα αρχικοποίηση — άλλαξε η βάση',
          data: const {'phase': 'reinit'},
        );
      } else {
        _write(
          LogSeverity.info,
          'νέα προσπάθεια εκκίνησης',
          data: const {'phase': 'retry'},
        );
      }
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
    _write(
      success ? LogSeverity.info : LogSeverity.warning,
      success
          ? 'ΕΤΟΙΜΗ — σύνολο βημάτων $total'
          : 'Η ΕΚΚΙΝΗΣΗ ΔΕΝ ΟΛΟΚΛΗΡΩΘΗΚΕ — σύνολο βημάτων $total',
      data: {'phase': 'end', 'success': success, 'total_ms': _totalMs},
    );
    _sealedOnce = true;
    _lastAttemptSucceeded = success;
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
      _writeStep(step);
      _totalMs += step.duration?.inMilliseconds ?? 0;
      _writtenCount++;
    }
  }

  /// Βήμα που δεν έκλεισε ποτέ. Γράφεται ρητά ως ημιτελές: η παράλειψη είναι
  /// ορατή, όχι σιωπηλή — ακριβώς όπως και στην οθόνη.
  void _flushUnfinishedSteps() {
    final steps = _journal.steps.value;
    while (_writtenCount < steps.length) {
      _writeStep(steps[_writtenCount], unfinished: true);
      _writtenCount++;
    }
  }

  void _writeStep(StartupStep step, {bool unfinished = false}) {
    final status = unfinished ? 'unfinished' : step.status.name;
    _write(
      _severityFor(step.status, unfinished: unfinished),
      step.label,
      details: _flatten(step.detail),
      data: {
        'phase': 'step',
        'status': status,
        if (step.duration != null) 'ms': step.duration!.inMilliseconds,
      },
    );
  }

  static LogSeverity _severityFor(
    StartupStepStatus status, {
    required bool unfinished,
  }) {
    if (unfinished) return LogSeverity.nonCritical;
    return switch (status) {
      StartupStepStatus.ok => LogSeverity.info,
      StartupStepStatus.skipped => LogSeverity.info,
      StartupStepStatus.running => LogSeverity.info,
      StartupStepStatus.warning => LogSeverity.warning,
      StartupStepStatus.failed => LogSeverity.nonCritical,
    };
  }

  void _write(
    LogSeverity severity,
    String message, {
    String? details,
    Map<String, Object?> data = const {},
  }) {
    append(
      LogRecord(
        time: _now(),
        kind: LogKind.startup,
        severity: severity,
        message: message,
        details: details,
        data: data,
      ),
    );
  }

  static String? _flatten(String? detail) {
    if (detail == null) return null;
    final single = detail.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.isEmpty) return null;
    if (single.length <= _maxDetailLength) return single;
    return '${single.substring(0, _maxDetailLength)}…';
  }
}
