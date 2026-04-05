import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_progress_provider.dart';
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
  }
  return result;
});
