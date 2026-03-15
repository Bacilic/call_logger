import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';

/// Provider για ρύθμιση εμφάνισης ενεργού χρονομέτρου στη φόρμα κλήσεων.
/// Invalidate μετά αλλαγή από την οθόνη ρυθμίσεων.
final showActiveTimerProvider =
    FutureProvider<bool>((ref) => SettingsService().getShowActiveTimer());
