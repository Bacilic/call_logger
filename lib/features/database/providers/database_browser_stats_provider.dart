import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/database_stats.dart';
import '../services/database_stats_service.dart';

/// Στατιστικά για την οθόνη περιήγησης βάσης· `autoDispose` ώστε ανανέωση όταν ξανα‐ανοίγει το tab.
final databaseBrowserStatsProvider =
    FutureProvider.autoDispose<DatabaseStats>((ref) async {
  return DatabaseStatsService.getDatabaseStats();
});
