import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_helper.dart';
import '../database/database_switch_success_notice.dart';
import 'app_init_provider.dart';
import 'database_reopen_cache_reset.dart';

/// Προαιρετικά σημεία σύνδεσης ανά οθόνη μετά από εναλλαγή βάσης.
class DatabaseSwitchCompletionHooks {
  const DatabaseSwitchCompletionHooks({
    this.onSessionStateUpdated,
    this.onLifecycleChanged,
  });

  /// Ενημέρωση τοπικής κατάστασης οθόνης (διαδρομή, σφάλματα, κ.λπ.).
  final Future<void> Function(String path)? onSessionStateUpdated;

  /// Επανασύνδεση / έλεγχοι κύκλου ζωής μετά το άνοιγμα της νέας βάσης.
  final Future<void> Function()? onLifecycleChanged;
}

/// Μόνο για τεστ — καταγραφή βημάτων της [completeDatabaseSwitch].
@visibleForTesting
List<String>? debugDatabaseSwitchCompletionSteps;

void _recordSwitchStep(String step) {
  debugDatabaseSwitchCompletionSteps?.add(step);
}

/// Ολοκληρώνει εναλλαγή βάσης με δεσμευτική σειρά βημάτων.
///
/// Η εκκαθάριση caches πρέπει να έρχεται ΠΑΝΤΑ μετά το άνοιγμα της νέας βάσης,
/// επειδή το [invalidateDatabaseScopedCaches] κάνει άμεσο
/// `ref.read(lookupServiceProvider)` και διαφορετικά ξαναγεμίζει από την
/// προηγούμενη βάση.
///
/// Δεν δέχεται [BuildContext] και δεν εμφανίζει διαλόγους — τεσταρίσιμη χωρίς
/// δέντρο widget.
Future<void> completeDatabaseSwitch({
  required WidgetRef ref,
  required String path,
  DatabaseSwitchCompletionHooks? hooks,
  bool showSuccessNotice = true,
}) async {
  // ΠΡΩΤΟ βήμα, πριν από κάθε άνοιγμα: μια ροή αποσφαλμάτωσης μπορεί να έχει
  // δεσμεύσει τη δοκιμαστική βάση. Όσο η δέσμευση ζει, κάθε άνοιγμα αγνοεί τη
  // ρυθμισμένη διαδρομή — η εφαρμογή θα ανακοίνωνε αλλαγή βάσης ενώ διαβάζει
  // ακόμα τη δοκιμαστική, με το κίτρινο «ΛΕΙΤΟΥΡΓΙΑ ΑΝΑΠΤΥΞΗΣ» κολλημένο.
  await DatabaseHelper.restoreConfiguredDatabasePath();
  _recordSwitchStep('restoreConfiguredPath');

  await hooks?.onSessionStateUpdated?.call(path);
  _recordSwitchStep('onSessionStateUpdated');

  await hooks?.onLifecycleChanged?.call();
  _recordSwitchStep('onLifecycleChanged');

  invalidateDatabaseScopedCaches(ref);
  _recordSwitchStep('invalidateCaches');

  ref.invalidate(appInitProvider);
  _recordSwitchStep('invalidateAppInit');

  if (showSuccessNotice) {
    ref.read(databaseSwitchSuccessNoticeProvider.notifier).show(path);
    _recordSwitchStep('successNotice');
  }
}
