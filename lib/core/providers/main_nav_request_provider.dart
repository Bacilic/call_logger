import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/main_nav_destination.dart';

/// Μονοσήμαντο αίτημα πλοήγησης από το audit ή άλλα σημεία· καταναλώνεται από το [MainShell].
class MainNavRequest {
  const MainNavRequest({
    required this.destination,
    this.directoryTabIndex,
    this.equipmentFocusEntityId,
    this.taskFocusEntityId,
    this.callFocusEntityId,
  });

  final MainNavDestination destination;

  /// Δείκτης καρτέλας Καταλόγου (0: Χρήστες, 1: Τμήματα, 2: Εξοπλισμός, 3: Διάφορα).
  final int? directoryTabIndex;

  /// `equipment.id` για εστίαση γραμμής στον πίνακα εξοπλισμού.
  final int? equipmentFocusEntityId;

  /// `tasks.id` για scroll στη λίστα εκκρεμοτήτων.
  final int? taskFocusEntityId;

  /// `calls.id` για μελλοντική εστίαση στην οθόνη κλήσεων (προαιρετικό).
  final int? callFocusEntityId;
}

class MainNavRequestNotifier extends Notifier<MainNavRequest?> {
  @override
  MainNavRequest? build() => null;

  void request(MainNavRequest r) {
    state = r;
  }

  void clear() {
    state = null;
  }
}

final mainNavRequestProvider =
    NotifierProvider<MainNavRequestNotifier, MainNavRequest?>(
  MainNavRequestNotifier.new,
);
