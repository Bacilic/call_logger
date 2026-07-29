import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/calls_screen_cards_visibility.dart';
import '../services/settings_service.dart';

/// Provider για ρύθμιση εμφάνισης ενεργού χρονομέτρου στη φόρμα κλήσεων.
/// Invalidate μετά αλλαγή από την οθόνη ρυθμίσεων.
final showActiveTimerProvider = FutureProvider<bool>(
  (ref) => SettingsService().windowUi.getShowActiveTimer(),
);

/// Εμφάνιση badge πλήθους εκκρεμοτήτων στο μενού. Invalidate μετά από Ρυθμίσεις.
final showTasksBadgeProvider = FutureProvider<bool>(
  (ref) => SettingsService().windowUi.getShowTasksBadge(),
);

/// Ορθογραφικός έλεγχος πεδίου σημειώσεων. Invalidate μετά από Ρυθμίσεις.
final enableSpellCheckProvider = FutureProvider<bool>(
  (ref) => SettingsService().windowUi.getEnableSpellCheck(),
);

/// Εμφάνιση προορισμού Βάση Δεδομένων στο NavigationRail. Invalidate μετά από Ρυθμίσεις.
final showDatabaseNavProvider = FutureProvider<bool>(
  (ref) => SettingsService().windowUi.getShowDatabaseNav(),
);

/// Εμφάνιση προορισμού Λάμπα (παλιά βάση) στο NavigationRail. Invalidate μετά από Ρυθμίσεις.
final showLampNavProvider = FutureProvider<bool>(
  (ref) => SettingsService().windowUi.getShowLampNav(),
);

/// Εμφάνιση προορισμού Λεξικό στο NavigationRail. Invalidate μετά από Ρυθμίσεις.
final showDictionaryNavProvider = FutureProvider<bool>(
  (ref) => SettingsService().windowUi.getShowDictionaryNav(),
);

/// Ορατότητα καρτελών οθόνης κλήσεων. Invalidate μετά από Ρυθμίσεις.
final callsScreenCardsVisibilityProvider =
    FutureProvider<CallsScreenCardsVisibility>(
      (ref) => SettingsService().windowUi.getCallsScreenCardsVisibility(),
    );

/// Εμφάνιση ιπτάμενου κουμπιού γρήγορης καταγραφής. Invalidate μετά από Ρυθμίσεις.
final showQuickCallFabProvider = FutureProvider<bool>(
  (ref) => SettingsService().windowUi.getShowQuickCallFab(),
);

// Πρότυπο/προεπιλογή προτροπής Gemini (SQLite app_settings): βλ. gemini_settings_provider —
// [geminiPromptTemplateProvider], [geminiPromptTemplateUserDefaultProvider].
