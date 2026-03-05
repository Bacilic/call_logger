import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_initializer.dart';

/// Provider αρχικοποίησης εφαρμογής. Τρέχει μία φορά στην εκκίνηση.
final appInitProvider = FutureProvider<AppInitResult>((ref) async {
  return AppInitializer.initialize();
});
