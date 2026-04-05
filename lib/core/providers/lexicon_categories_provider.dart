import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';

/// Κατηγορίες λεξικού από `app_settings` (ορίζονται στο διάλογο ρυθμίσεων λεξικού).
final lexiconCategoriesProvider = FutureProvider<List<String>>((ref) async {
  return SettingsService().getLexiconCategoriesList();
});
