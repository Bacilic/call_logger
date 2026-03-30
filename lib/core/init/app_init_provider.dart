import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_initializer.dart';

/// Provider αρχικοποίησης εφαρμογής. Τρέχει μία φορά στην εκκίνηση.
final appInitProvider = FutureProvider<AppInitResult>((ref) async {
  final result = await AppInitializer.initialize();
  if (result.success) {
    await AppInitializer.activateBackupSchedulingAfterDatabaseReady(ref);
  }
  return result;
});
