import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';
import '../widgets/main_nav_destination.dart';

/// Τρέχων αποτελεσματικός προορισμός [MainShell] — ενημερώνεται από το κέλυφος.
final mainShellEffectiveDestinationProvider =
    NotifierProvider<MainShellEffectiveDestinationNotifier, MainNavDestination>(
      MainShellEffectiveDestinationNotifier.new,
    );

class MainShellEffectiveDestinationNotifier extends Notifier<MainNavDestination> {
  @override
  MainNavDestination build() => MainNavDestination.calls;

  void setDestination(MainNavDestination destination) {
    if (state == destination) return;
    state = destination;
  }
}

/// True όταν η οθόνη Ρυθμίσεων είναι ανοιχτή πάνω από το κέλυφος.
final settingsRouteOpenForQuickCallProvider =
    NotifierProvider<SettingsRouteOpenForQuickCallNotifier, bool>(
      SettingsRouteOpenForQuickCallNotifier.new,
    );

class SettingsRouteOpenForQuickCallNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setOpen(bool open) => state = open;
}

/// True όταν ο χάρτης κτιρίου είναι σε λειτουργία επεξεργασίας.
final buildingMapQuickCallBlockedProvider =
    NotifierProvider<BuildingMapQuickCallBlockedNotifier, bool>(
      BuildingMapQuickCallBlockedNotifier.new,
    );

class BuildingMapQuickCallBlockedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setBlocked(bool blocked) => state = blocked;
}

bool isQuickCallFabEnabled(WidgetRef ref) {
  return ref.watch(showQuickCallFabProvider).value ?? true;
}

bool isQuickCallOverlayBlocked(WidgetRef ref) {
  if (ref.watch(buildingMapQuickCallBlockedProvider)) return true;
  return false;
}

/// FAB σε routes πάνω από το κέλυφος (Ρυθμίσεις, Στατιστικά, προβολή χάρτη).
bool isQuickCallOverlayFabAvailable(WidgetRef ref) {
  if (!isQuickCallFabEnabled(ref)) return false;
  if (isQuickCallOverlayBlocked(ref)) return false;
  return true;
}

/// Κεντρικός έλεγχος διαθεσιμότητας (immersive FAB / συντόμευση).
bool isQuickCallCaptureAvailable(WidgetRef ref) {
  if (!isQuickCallFabEnabled(ref)) return false;
  if (isQuickCallOverlayBlocked(ref)) return false;
  if (ref.watch(settingsRouteOpenForQuickCallProvider)) return true;
  final destination = ref.watch(mainShellEffectiveDestinationProvider);
  if (destination == MainNavDestination.calls) return false;
  return true;
}
