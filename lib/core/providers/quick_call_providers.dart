import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quick_call_fab_places.dart';
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

/// True όσο είναι ανοιχτή η Σχεδίαση χάρτη. Ανοίγει πάνω από την Επεξεργασία
/// του χάρτη, αλλά η γρήγορη κλήση επιτρέπεται: η σχεδίαση κρατά ό,τι
/// σχεδιάστηκε, και η κλήση ανοίγει από πάνω.
final floorPlanDesignOpenProvider =
    NotifierProvider<FloorPlanDesignOpenNotifier, bool>(
      FloorPlanDesignOpenNotifier.new,
    );

class FloorPlanDesignOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setOpen(bool open) => state = open;
}

/// Το κουμπί γρήγορης κλήσης φαίνεται στο [place] κατά τις Ρυθμίσεις.
bool isQuickCallFabShownAt(WidgetRef ref, QuickCallFabPlace place) {
  final places = ref.watch(quickCallFabPlacesProvider).value;
  return places?.shows(place) ?? true;
}

bool isQuickCallOverlayBlocked(WidgetRef ref) {
  if (ref.watch(floorPlanDesignOpenProvider)) return false;
  return ref.watch(buildingMapQuickCallBlockedProvider);
}

/// Κεντρικός έλεγχος διαθεσιμότητας της γρήγορης καταγραφής — σε κάθε οθόνη,
/// και στην οθόνη Κλήσεων: εκεί η γρήγορη καταγραφή είναι η δεύτερη κλήση.
///
/// Δεν εξαρτάται από το αν φαίνεται το κουμπί: η συντόμευση δουλεύει παντού.
bool isQuickCallCaptureAvailable(WidgetRef ref) {
  return !isQuickCallOverlayBlocked(ref);
}
