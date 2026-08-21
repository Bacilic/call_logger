import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_permission.dart';
import '../models/calls_screen_cards_visibility.dart';
import '../services/permission_service.dart';
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
///
/// **Η ωμή προτίμηση του χρήστη — αυτήν διαβάζει και γράφει ο διακόπτης των
/// Ρυθμίσεων.** Για το αν ο προορισμός φαίνεται όντως, χρησιμοποίησε το
/// [databaseNavVisibleProvider]: εκεί μπαίνει και το δικαίωμα. Αν το δικαίωμα
/// έμπαινε εδώ, ο διακόπτης θα έδειχνε «κλειστό» και δεν θα άνοιγε ποτέ.
final showDatabaseNavProvider = FutureProvider<bool>(
  (ref) => SettingsService().windowUi.getShowDatabaseNav(),
);

/// Φαίνεται τελικά η Περιήγηση Βάσης; **Προτίμηση ΚΑΙ δικαίωμα.**
///
/// Μοναδικό σημείο για κάθε πύλη που οδηγεί εκεί — σήμερα η πλευρική μπάρα και
/// τα μενού πλοήγησης του Ιστορικού και του Λεξικού. Κάθε νέα πύλη ρωτά εδώ
/// και κληρονομεί αυτόματα τον έλεγχο.
///
/// Όσο η προτίμηση φορτώνει, ο προορισμός φαίνεται — ίδια συμπεριφορά με πριν.
final databaseNavVisibleProvider = Provider<bool>((ref) {
  final preference = ref
      .watch(showDatabaseNavProvider)
      .maybeWhen(data: (value) => value, orElse: () => true);
  if (!preference) return false;
  return PermissionService.instance.can(AppPermission.browseDatabase);
});

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
