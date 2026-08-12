import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../init/startup_journal.dart';

/// Τι σημαίνει μια κλήση [DatabaseInitProgressNotifier.setStep] για το
/// ημερολόγιο εκκίνησης.
///
/// Χωρίς αυτό, η μόνη διάκριση θα ήταν το κείμενο του βήματος — συμβόλαιο που
/// σπάει σιωπηλά την πρώτη φορά που κάποιος διορθώσει μια διατύπωση.
enum StartupStepKind {
  /// Νέο βήμα: κλείνει το προηγούμενο και ανοίγει δική του γραμμή.
  step,

  /// Σφραγίδα ολοκλήρωσης: κλείνει το τρέχον βήμα χωρίς να ανοίξει γραμμή.
  completed,

  /// Σφραγίδα αποτυχίας: κλείνει το τρέχον βήμα ως αποτυχία.
  failed,
}

/// Κατάσταση προόδου αρχικοποίησης βάσης δεδομένων.
class DatabaseInitProgressState {
  const DatabaseInitProgressState({
    required this.currentStep,
    this.secondsRemaining,
    this.diagnosticInfo,
    this.isOpeningAttemptActive = false,
  });

  factory DatabaseInitProgressState.initial() {
    return const DatabaseInitProgressState(
      currentStep: 'Εκκίνηση...',
      secondsRemaining: null,
      diagnosticInfo: null,
      isOpeningAttemptActive: false,
    );
  }

  final String currentStep;
  final int? secondsRemaining;
  final String? diagnosticInfo;
  final bool isOpeningAttemptActive;

  DatabaseInitProgressState copyWith({
    String? currentStep,
    int? secondsRemaining,
    bool clearSecondsRemaining = false,
    String? diagnosticInfo,
    bool clearDiagnosticInfo = false,
    bool? isOpeningAttemptActive,
  }) {
    return DatabaseInitProgressState(
      currentStep: currentStep ?? this.currentStep,
      secondsRemaining: clearSecondsRemaining
          ? null
          : (secondsRemaining ?? this.secondsRemaining),
      diagnosticInfo: clearDiagnosticInfo
          ? null
          : (diagnosticInfo ?? this.diagnosticInfo),
      isOpeningAttemptActive:
          isOpeningAttemptActive ?? this.isOpeningAttemptActive,
    );
  }
}

/// Notifier προόδου αρχικοποίησης βάσης.
class DatabaseInitProgressNotifier extends Notifier<DatabaseInitProgressState> {
  @override
  DatabaseInitProgressState build() => DatabaseInitProgressState.initial();

  /// Η ανοιχτή γραμμή του ημερολογίου. Κάθε νέο βήμα την κλείνει πρώτα.
  StartupStepHandle? _openStep;

  void reset() {
    state = DatabaseInitProgressState.initial();
    _openStep = null;
  }

  void setStep(
    String step, {
    int? secondsRemaining,
    String? diagnosticInfo,
    bool clearSecondsRemaining = false,
    bool clearDiagnosticInfo = false,
    StartupStepKind kind = StartupStepKind.step,
  }) {
    _journalStep(step, kind: kind, isCountdown: secondsRemaining != null);
    state = state.copyWith(
      currentStep: step,
      secondsRemaining: secondsRemaining,
      clearSecondsRemaining: clearSecondsRemaining,
      diagnosticInfo: diagnosticInfo,
      clearDiagnosticInfo: clearDiagnosticInfo,
      isOpeningAttemptActive: clearSecondsRemaining
          ? false
          : (secondsRemaining != null ? true : state.isOpeningAttemptActive),
    );
  }

  void clearCountdown() {
    state = state.copyWith(
      clearSecondsRemaining: true,
      isOpeningAttemptActive: false,
    );
  }

  void setDiagnostic(String? diagnosticInfo) {
    if (diagnosticInfo == null || diagnosticInfo.trim().isEmpty) return;
    state = state.copyWith(diagnosticInfo: diagnosticInfo.trim());
  }

  /// Μεταφράζει την πρόοδο σε γραμμές ημερολογίου.
  ///
  /// Η αντίστροφη μέτρηση του ανοίγματος καλεί [setStep] μία φορά το
  /// δευτερόλεπτο· χωρίς τον έλεγχο [isCountdown] θα άφηνε πέντε πανομοιότυπες
  /// γραμμές αντί για μία που μετρά.
  void _journalStep(
    String step, {
    required StartupStepKind kind,
    required bool isCountdown,
  }) {
    final journal = StartupJournal.instance;
    switch (kind) {
      case StartupStepKind.completed:
        _openStep?.ok();
        _openStep = null;
      case StartupStepKind.failed:
        _openStep?.fail(step);
        _openStep = null;
      case StartupStepKind.step:
        if (isCountdown && _openStep != null) {
          _openStep!.relabel(step);
          return;
        }
        _openStep?.ok();
        _openStep = journal.begin(step);
    }
  }
}

final databaseInitProgressProvider =
    NotifierProvider<DatabaseInitProgressNotifier, DatabaseInitProgressState>(
      DatabaseInitProgressNotifier.new,
    );
