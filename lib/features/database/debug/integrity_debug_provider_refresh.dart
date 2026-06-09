import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/calls/provider/lookup_provider.dart';
import '../../../features/tasks/providers/tasks_provider.dart';
import '../providers/database_browser_stats_provider.dart';
import '../providers/database_integrity_provider.dart';
import 'integrity_debug_seeder_service.dart';

/// Provider για τον debug seeder (μόνο debug/desktop — το UI ελέγχει [IntegrityDebugSeederService.isEnabled]).
final integrityDebugSeederServiceProvider = Provider<IntegrityDebugSeederService>(
  (ref) => IntegrityDebugSeederService(),
);

/// Ανανέωση Riverpod state μετά την ενεργοποίηση της `integrity_debug.db`.
Future<void> refreshProvidersAfterIntegrityDebugSwitch(WidgetRef ref) async {
  ref.read(databaseIntegrityProvider.notifier).reset();
  ref.invalidate(databaseBrowserStatsProvider);
  ref.invalidate(lookupServiceProvider);
  ref.invalidate(tasksProvider);
  ref.invalidate(orphanCallsProvider);
  await ref.read(databaseIntegrityProvider.notifier).runCheck(force: true);
}
