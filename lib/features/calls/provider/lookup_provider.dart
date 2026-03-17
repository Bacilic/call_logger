import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/lookup_service.dart';

/// Provider που φορτώνει το LookupService μία φορά κατά το init.
final lookupServiceProvider = FutureProvider<LookupService>((ref) async {
  final service = LookupService.instance;
  service.resetForReload();
  await service.loadFromDatabase();
  return service;
});
