import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_progress_provider.dart';
import '../database/department_floor_migration.dart';
import '../services/audit_retention_runner.dart';
import 'app_initializer.dart';

/// Provider αρχικοποίησης εφαρμογής. Τρέχει μία φορά στην εκκίνηση.
final appInitProvider = FutureProvider<AppInitResult>((ref) async {
  // Μην τροποποιείς άλλους providers συγχρονισμένα κατά το mount του FutureProvider
  // (Riverpod: «Providers are not allowed to modify other providers during their initialization»).
  await Future<void>.delayed(Duration.zero);
  final progressNotifier = ref.read(databaseInitProgressProvider.notifier);
  progressNotifier.reset();
  final result = await AppInitializer.initialize(
    progressNotifier: progressNotifier,
  );
  if (result.success) {
    await AppInitializer.activateBackupSchedulingAfterDatabaseReady(ref);
    try {
      await AuditRetentionRunner.applyIfConfiguredOnStartup();
    } catch (_) {
      // Soft-fail: η εκκίνηση δεν μπλοκάρεται από retention.
    }
    try {
      await DepartmentFloorMigrationRunner.runIfNeeded();
    } catch (_) {
      // Soft-fail: συμπλήρωση floor_id δεν πρέπει να μπλοκάρει την εκκίνηση.
    }
  }
  return result;
});
