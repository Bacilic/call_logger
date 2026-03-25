import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';

/// Provider για ρύθμιση εμφάνισης ενεργού χρονομέτρου στη φόρμα κλήσεων.
/// Invalidate μετά αλλαγή από την οθόνη ρυθμίσεων.
final showActiveTimerProvider =
    FutureProvider<bool>((ref) => SettingsService().getShowActiveTimer());

/// Provider για εμφάνιση κουμπιού AnyDesk στη φόρμα κλήσεων. Προεπιλογή: true.
/// Invalidate μετά αλλαγή από την οθόνη ρυθμίσεων.
final showAnyDeskRemoteProvider =
    FutureProvider<bool>((ref) => SettingsService().getShowAnyDeskRemote());

/// Εμφάνιση badge πλήθους εκκρεμοτήτων στο μενού. Invalidate μετά από Ρυθμίσεις.
final showTasksBadgeProvider =
    FutureProvider<bool>((ref) => SettingsService().getShowTasksBadge());

/// Ορθογραφικός έλεγχος πεδίου σημειώσεων. Invalidate μετά από Ρυθμίσεις.
final enableSpellCheckProvider =
    FutureProvider<bool>((ref) => SettingsService().getEnableSpellCheck());
