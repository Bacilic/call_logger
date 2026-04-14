import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Κατανάλωση από [EquipmentTab]: εστίαση γραμμής κατά `equipment.id`.
class EquipmentFocusIntentNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void focus(int equipmentId) {
    state = equipmentId;
  }

  void clear() {
    state = null;
  }
}

final equipmentFocusIntentProvider =
    NotifierProvider<EquipmentFocusIntentNotifier, int?>(
  EquipmentFocusIntentNotifier.new,
);
