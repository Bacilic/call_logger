import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/database_integrity_report.dart';
import '../services/database_integrity_service.dart';

/// Κατάσταση ελέγχου ακεραιότητας βάσης.
sealed class DatabaseIntegrityState {
  const DatabaseIntegrityState();
}

final class DatabaseIntegrityIdle extends DatabaseIntegrityState {
  const DatabaseIntegrityIdle();
}

final class DatabaseIntegrityLoading extends DatabaseIntegrityState {
  const DatabaseIntegrityLoading({
    required this.currentStep,
    required this.totalSteps,
    required this.currentCheckName,
    required this.totalRowsChecked,
    this.tableScopeLabel,
  });

  final int currentStep;
  final int totalSteps;
  final String currentCheckName;
  final int totalRowsChecked;
  final String? tableScopeLabel;
}

final class DatabaseIntegritySuccess extends DatabaseIntegrityState {
  const DatabaseIntegritySuccess(this.report);
  final DatabaseIntegrityReport report;
}

final class DatabaseIntegrityError extends DatabaseIntegrityState {
  const DatabaseIntegrityError(this.message);
  final String message;
}

final databaseIntegrityServiceProvider = Provider<DatabaseIntegrityService>(
  (ref) => DatabaseIntegrityService(),
);

class DatabaseIntegrityNotifier extends Notifier<DatabaseIntegrityState> {
  @override
  DatabaseIntegrityState build() => const DatabaseIntegrityIdle();

  Future<void> runCheck() async {
    if (state is DatabaseIntegrityLoading) return;

    state = const DatabaseIntegrityLoading(
      currentStep: 0,
      totalSteps: DatabaseIntegrityService.totalSteps,
      currentCheckName: 'Προετοιμασία…',
      totalRowsChecked: 0,
    );

    try {
      final service = ref.read(databaseIntegrityServiceProvider);
      final report = await service.runChecks(
        onProgress: (progress) {
          state = DatabaseIntegrityLoading(
            currentStep: progress.currentStep,
            totalSteps: progress.totalSteps,
            currentCheckName: progress.currentCheckName,
            totalRowsChecked: progress.totalRowsChecked,
            tableScopeLabel: progress.tableScopeLabel,
          );
        },
      );
      state = DatabaseIntegritySuccess(report);
    } catch (e) {
      state = DatabaseIntegrityError('$e');
    }
  }

  void reset() {
    state = const DatabaseIntegrityIdle();
  }
}

final databaseIntegrityProvider =
    NotifierProvider<DatabaseIntegrityNotifier, DatabaseIntegrityState>(
  DatabaseIntegrityNotifier.new,
);
