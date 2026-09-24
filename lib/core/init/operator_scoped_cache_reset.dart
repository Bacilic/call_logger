import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/provider/calls_dashboard_providers.dart';
import '../../features/calls/provider/remote_paths_provider.dart';
import '../../features/database/providers/database_backup_settings_provider.dart';
import '../../features/dictionary/providers/lexicon_list_filters_provider.dart';
import '../../features/directory/providers/catalog_continuous_scroll_provider.dart';
import '../../features/directory/providers/category_directory_provider.dart';
import '../../features/directory/providers/department_directory_provider.dart';
import '../../features/directory/providers/directory_provider.dart';
import '../../features/directory/providers/equipment_directory_provider.dart';
import '../../features/history/providers/dashboard_provider.dart';
import '../../features/history/providers/gemini_settings_provider.dart';
import '../../features/history/providers/history_application_audit_view_provider.dart';
import '../../features/history/providers/lansweeper_report_scope_provider.dart';
import '../../features/tasks/providers/task_analytics_date_provider.dart';
import '../../features/tasks/providers/task_notifications_provider.dart';
import '../providers/history_audit_immersive_provider.dart';
import '../providers/settings_provider.dart';
import '../services/current_operator.dart';

/// Εκκαθάριση των caches που κρατούν **προσωπικές ρυθμίσεις του προηγούμενου
/// χρήστη**, μετά από «Αλλαγή χρήστη».
///
/// ΚΑΘΕ provider που διαβάζει ρύθμιση εμβέλειας ΠΡΟΦΙΛ ανήκει εδώ. Αλλιώς η
/// οθόνη που τον διαβάζει συνεχίζει να δείχνει την επιλογή του προηγούμενου
/// μέχρι να κλείσει και να ξανανοίξει — ακριβώς αυτό συνέβαινε με την πλευρική
/// μπάρα, που κρατούσε τους προορισμούς του προηγούμενου χρήστη.
///
/// **Η λίστα ζει σε ΕΝΑ σημείο επίτηδες:** κάθε νέα προσωπική ρύθμιση που
/// αποκτά provider προστίθεται εδώ, ώστε να μη μείνει κανείς έξω.
///
/// Καλείται **μόνο από το widget layer** ([WidgetRef]) και ποτέ μέσα από
/// provider: ακύρωση από provider layer καταλήγει σε «setState during build»
/// όταν η αλυσίδα ξεπλυθεί σύγχρονα μέσα σε build άλλης οθόνης. Για τον ίδιο
/// λόγο η εκτέλεση αναβάλλεται όταν τρέχει frame.
///
/// Οι providers που **ακυρώνονται** εδώ είναι φύλλα: διαβάζουν ρύθμιση, δεν
/// εξαρτώνται από άλλον provider που ακυρώνεται μαζί τους, και ξαναδιαβάζουν
/// μόνοι τους στο `build` — οπότε δεν χρειάζονται eager flush.
///
/// **Η διάκριση που κάνει τη διαφορά:** ακύρωση επιτρέπεται μόνο σε providers
/// που κρατούν **ρύθμιση**. Όποιος κρατά **δεδομένα** (οι καρτέλες Καταλόγου)
/// ανανεώνεται με στοχευμένη κλήση που ξαναδιαβάζει τις προτιμήσεις και αφήνει
/// τις εγγραφές στη θέση τους — η βάση δεν άλλαξε, μόνο ο χρήστης.
///
/// **Δύο αφορμές, δύο εμβέλειες** ([cause]):
///
/// - `identitySwitched` — κάθισε άλλος άνθρωπος. Ξαναδιαβάζονται όλα, και οι
///   οθόνες που δεν δικαιούται κλείνουν.
/// - `profileRefreshed` — ο διαχειριστής άλλαξε κάτι από άλλον σταθμό, αλλά
///   στην καρέκλα κάθεται ο ίδιος. Ανανεώνονται **μόνο τα δικαιώματα**: οι
///   προσωπικές του ρυθμίσεις δεν άλλαξαν, και καμία ανοιχτή οθόνη δεν του
///   κλείνει στη μέση της δουλειάς του. Έτσι η ανανέωση κοστίζει δύο ακυρώσεις
///   αντί για είκοσι πέντε συν τέσσερις επαναφορτώσεις στηλών — και μπορεί να
///   τρέχει με τον κύκλο φρεσκάδας χωρίς να βαραίνει τίποτα.
void invalidateOperatorScopedCaches(
  WidgetRef ref, {
  OperatorChangeCause cause = OperatorChangeCause.identitySwitched,
}) {
  void run() {
    if (!ref.context.mounted) return;

    // Τα δικαιώματα δεν είναι providers — διαβάζονται από τον συνδεδεμένο
    // χρήστη τη στιγμή του υπολογισμού. Ακυρώνονται και στις δύο αφορμές:
    // είναι το μόνο που αλλάζει όταν μιλά ο διαχειριστής από αλλού.
    ref.invalidate(databaseNavVisibleProvider);
    ref.invalidate(applicationAuditVisibleProvider);

    if (cause == OperatorChangeCause.profileRefreshed) {
      // Και τίποτα άλλο. Ο ίδιος άνθρωπος κάθεται: οι προτιμήσεις του ισχύουν,
      // οι πίνακές του δεν ξαναφορτώνονται, και ό,τι έχει ανοιχτό μένει
      // ανοιχτό. Το νέο δικαίωμα κρίνει την επόμενη φορά που θα ζητηθεί η
      // πόρτα — τα δικαιώματα σταματούν το λάθος, όχι τη δουλειά.
      return;
    }

    // Πλευρική μπάρα και ορατότητα στοιχείων — ό,τι βλέπει ο χρήστης αμέσως.
    ref.invalidate(showActiveTimerProvider);
    ref.invalidate(showTasksBadgeProvider);
    // Ο παραλήπτης των ειδοποιήσεων ΕΙΝΑΙ ο συνδεδεμένος χρήστης: χωρίς αυτό,
    // ο επόμενος που θα καθίσει θα έβλεπε όσα περίμεναν τον προηγούμενο.
    ref.invalidate(notifyTaskHandoversProvider);
    ref.invalidate(taskNotificationsProvider);
    ref.invalidate(enableSpellCheckProvider);
    // Ξανά μετά τη ρύθμιση από κάτω του: το `databaseNavVisibleProvider`
    // συνδυάζει προτίμηση ΚΑΙ δικαίωμα, οπότε η ακύρωση της προτίμησης πρέπει
    // να ακολουθηθεί από δική του — αλλιώς κρατά το παλιό αποτέλεσμα.
    ref.invalidate(showDatabaseNavProvider);
    ref.invalidate(databaseNavVisibleProvider);
    // Το τικ είναι υπόσχεση: όποιος δεν το έχει δεν μένει σε οθόνη που δεν
    // δικαιούται, ακόμη κι αν την άνοιξε ο προηγούμενος.
    closeApplicationAuditIfNotAllowed(
      allowed: ref.read(applicationAuditVisibleProvider),
      view: ref.read(historyApplicationAuditViewProvider.notifier),
      immersive: ref.read(historyAuditImmersiveProvider.notifier),
    );
    ref.invalidate(showLampNavProvider);
    ref.invalidate(showDictionaryNavProvider);
    ref.invalidate(showKnowledgeNavProvider);
    ref.invalidate(callsScreenCardsVisibilityProvider);
    ref.invalidate(showQuickCallFabProvider);
    ref.invalidate(showGlobalCallsToggleProvider);

    // Κατάλογος: ορατές στήλες και σειρά ανά καρτέλα.
    //
    // **ΠΟΤΕ `invalidate` εδώ.** Οι καρτέλες ξεκινούν από ΚΕΝΗ κατάσταση και
    // γεμίζουν μόνο όταν ανοίγουν· ακύρωση με την καρτέλα ήδη ανοιχτή αδειάζει
    // τον πίνακα μπροστά στα μάτια του χρήστη (αναφορά 20/08/2026). Η βάση δεν
    // άλλαξε — μόνο οι προτιμήσεις προβολής — οπότε ξαναδιαβάζονται μόνο αυτές
    // και τα δεδομένα μένουν στη θέση τους.
    unawaited(
      ref
          .read(directoryProvider.notifier)
          .reloadColumnLayoutForCurrentOperator(),
    );
    unawaited(
      ref
          .read(equipmentDirectoryProvider.notifier)
          .reloadColumnLayoutForCurrentOperator(),
    );
    unawaited(
      ref
          .read(departmentDirectoryProvider.notifier)
          .reloadColumnLayoutForCurrentOperator(),
    );
    unawaited(
      ref
          .read(categoryDirectoryProvider.notifier)
          .reloadColumnLayoutForCurrentOperator(),
    );

    // Οι διακόπτες «συνεχής κύλιση» κρατούν **ρύθμιση**, όχι εγγραφές —
    // η ακύρωση δεν αδειάζει κανέναν πίνακα.
    ref.invalidate(catalogUsersContinuousScrollProvider);
    ref.invalidate(catalogDepartmentsContinuousScrollProvider);
    ref.invalidate(catalogEquipmentContinuousScrollProvider);

    // Στατιστικά κλήσεων και εκκρεμοτήτων: φίλτρα ημερομηνιών και διακόπτες.
    ref.invalidate(dashboardFilterProvider);
    ref.invalidate(dashboardExcludeCallsWithoutCategoryProvider);
    ref.invalidate(dashboardHideUnknownCallerProvider);
    ref.invalidate(dashboardHideUnknownTopCallerProvider);
    ref.invalidate(dashboardPaletteProvider);
    ref.invalidate(taskAnalyticsDateProvider);

    // Λεξικό, εργαλεία κλήσεων, ΤΝ, Αναφορά Lansweeper.
    ref.invalidate(lexiconListFiltersProvider);
    ref.invalidate(remoteToolsCatalogProvider);
    ref.invalidate(geminiPromptTemplateProvider);
    ref.invalidate(lansweeperReportScopeProvider);

    // Το «δέμα» των αντιγράφων ακούει ήδη μόνο του την αλλαγή ταυτότητας, αλλά
    // η ακύρωση εδώ κρατά την εικόνα ενιαία: ένα σημείο απαντά «τι ανανεώνεται
    // όταν αλλάζει χρήστης».
    ref.invalidate(databaseBackupSettingsProvider);
  }

  final phase = SchedulerBinding.instance.schedulerPhase;
  final safeToRunNow =
      phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks;
  if (safeToRunNow) {
    run();
  } else {
    SchedulerBinding.instance.addPostFrameCallback((_) => run());
  }
}
