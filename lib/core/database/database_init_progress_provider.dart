import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Κατάσταση προόδου αρχικοποίησης βάσης δεδομένων.
class DatabaseInitProgressState {
  const DatabaseInitProgressState({
    required this.currentStep,
    this.secondsRemaining,
    this.diagnosticInfo,
  });

  factory DatabaseInitProgressState.initial() {
    return const DatabaseInitProgressState(
      currentStep: 'Εκκίνηση...',
      secondsRemaining: null,
      diagnosticInfo: null,
    );
  }

  final String currentStep;
  final int? secondsRemaining;
  final String? diagnosticInfo;

  DatabaseInitProgressState copyWith({
    String? currentStep,
    int? secondsRemaining,
    bool clearSecondsRemaining = false,
    String? diagnosticInfo,
    bool clearDiagnosticInfo = false,
  }) {
    return DatabaseInitProgressState(
      currentStep: currentStep ?? this.currentStep,
      secondsRemaining: clearSecondsRemaining
          ? null
          : (secondsRemaining ?? this.secondsRemaining),
      diagnosticInfo: clearDiagnosticInfo
          ? null
          : (diagnosticInfo ?? this.diagnosticInfo),
    );
  }
}

/// Notifier προόδου αρχικοποίησης βάσης.
class DatabaseInitProgressNotifier extends Notifier<DatabaseInitProgressState> {
  @override
  DatabaseInitProgressState build() => DatabaseInitProgressState.initial();

  void reset() {
    state = DatabaseInitProgressState.initial();
  }

  void setStep(
    String step, {
    int? secondsRemaining,
    String? diagnosticInfo,
    bool clearSecondsRemaining = false,
    bool clearDiagnosticInfo = false,
  }) {
    state = state.copyWith(
      currentStep: step,
      secondsRemaining: secondsRemaining,
      clearSecondsRemaining: clearSecondsRemaining,
      diagnosticInfo: diagnosticInfo,
      clearDiagnosticInfo: clearDiagnosticInfo,
    );
  }

  void clearCountdown() {
    state = state.copyWith(clearSecondsRemaining: true);
  }

  void setDiagnostic(String? diagnosticInfo) {
    if (diagnosticInfo == null || diagnosticInfo.trim().isEmpty) return;
    state = state.copyWith(diagnosticInfo: diagnosticInfo.trim());
  }
}

final databaseInitProgressProvider =
    NotifierProvider<DatabaseInitProgressNotifier, DatabaseInitProgressState>(
      DatabaseInitProgressNotifier.new,
    );
