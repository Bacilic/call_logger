import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_permission.dart';
import '../../../core/providers/database_settings_route_intent_provider.dart';
import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/providers/settings_route_intent_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../providers/remote_tools_view_intent_provider.dart';
import 'path_fix_destination.dart';

/// Καρτέλα «Αντίγραφα ασφαλείας» μέσα στις Ρυθμίσεις βάσης.
const int _kBackupSettingsTabIndex = 1;

/// Γιατί δεν μπορεί να προσφερθεί η μετάβαση· `null` = μπορεί.
///
/// Μία απόφαση για όλους τους λόγους, ώστε ο καλών να μη μπορεί να ελέγξει το
/// δικαίωμα και να ξεχάσει την ορατότητα — ή το αντίστροφο. Το κείμενο που
/// επιστρέφει είναι η υπόδειξη του ανενεργού κουμπιού.
String? pathFixBlockedReason(
  PathFixDestination destination, {
  required bool dictionaryNavVisible,
  bool Function(AppPermission permission)? can,
}) {
  final permission = destination.requiredPermission;
  if (permission != null) {
    final check = can ?? PermissionService.instance.can;
    if (!check(permission)) {
      return 'Η ρύθμιση «${permission.label}» αλλάζει μόνο από χρήστη που '
          'έχει το σχετικό δικαίωμα.';
    }
  }
  // Ο διάλογος των διαδρομών λεξικού ζει μέσα στην οθόνη Λεξικού: κρυμμένη η
  // οθόνη, δεν υπάρχει πού να πάει το κουμπί.
  if (destination == PathFixDestination.dictionaryPaths &&
      !dictionaryNavVisible) {
    return 'Το Λεξικό είναι κρυμμένο από την πλευρική μπάρα. Εμφανίστε το από '
        'τις Ρυθμίσεις για να φτάσετε στις διαδρομές του.';
  }
  return null;
}

/// Στέλνει τον χρήστη στο σημείο που διορθώνεται η διαδρομή.
///
/// Κάθε προορισμός φτάνει **μέχρι το πεδίο**: όπου η ρύθμιση ζει μέσα σε
/// διάλογο, ζητιέται και το άνοιγμα του διαλόγου, όχι μόνο η οθόνη που τον
/// φιλοξενεί.
void requestPathFixNavigation(WidgetRef ref, PathFixDestination destination) {
  switch (destination) {
    case PathFixDestination.backupSettings:
      // Χωρίς αλλαγή οθόνης: ο διάλογος ανοίγει από πάνω, οπότε ο έλεγχος
      // που μόλις έτρεξε μένει εκεί που τον άφησε ο χρήστης.
      ref
          .read(databaseSettingsRouteIntentProvider.notifier)
          .openTab(_kBackupSettingsTabIndex);
    case PathFixDestination.remoteTools:
      ref.read(remoteToolsViewRequestProvider.notifier).request();
    case PathFixDestination.updateFolder:
      ref
          .read(settingsRouteIntentProvider.notifier)
          .openSection(SettingsSection.updates);
    case PathFixDestination.dictionaryPaths:
      ref
          .read(mainNavRequestProvider.notifier)
          .request(
            const MainNavRequest(
              destination: MainNavDestination.dictionary,
              openDictionarySettings: true,
            ),
          );
  }
}
