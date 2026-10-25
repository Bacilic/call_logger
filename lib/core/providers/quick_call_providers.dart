import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

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

/// Κεντρικός έλεγχος διαθεσιμότητας (κουμπί / συντόμευση) — σε κάθε οθόνη,
/// και στην οθόνη Κλήσεων: εκεί η γρήγορη καταγραφή είναι η δεύτερη κλήση.
bool isQuickCallCaptureAvailable(WidgetRef ref) {
  if (!isQuickCallFabEnabled(ref)) return false;
  if (isQuickCallOverlayBlocked(ref)) return false;
  return true;
}
