/// Πού εμφανίζεται το κύριο παράθυρο κατά την εκκίνηση (Windows desktop).
enum WindowPlacementMode {
  /// Επαναφορά τελευταίας θέσης (και μεγέθους) όταν τερματίστηκε η εφαρμογή.
  lastPosition,

  /// Κεντράρισμα στην κύρια οθόνη σε κάθε εκκίνηση.
  alwaysCenter,
}

extension WindowPlacementModeStorage on WindowPlacementMode {
  String get storageValue => switch (this) {
        WindowPlacementMode.lastPosition => 'last',
        WindowPlacementMode.alwaysCenter => 'center',
      };

  static WindowPlacementMode? fromStorage(String? raw) {
    return switch (raw) {
      'last' => WindowPlacementMode.lastPosition,
      'center' => WindowPlacementMode.alwaysCenter,
      _ => null,
    };
  }

  String get settingsLabel => switch (this) {
        WindowPlacementMode.lastPosition =>
          'Τελευταία θέση κατά τον τερματισμό',
        WindowPlacementMode.alwaysCenter => 'Πάντα στο κέντρο της οθόνης',
      };
}
