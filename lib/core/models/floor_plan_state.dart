import 'dart:ui' show Offset;

/// Η κατάσταση του νέου χάρτη για έναν όροφο — **χωρίς την εικόνα** του
/// πατρόν, που διαβάζεται χωριστά μόνο όταν χρειάζεται.
///
/// Το πατρόν τοποθετείται στον χώρο του σχεδίου με το κέντρο του
/// ([patternCenter], σε εκατοστά), την κλίμακά του ([cmPerPixel]: πόσα
/// εκατοστά πραγματικού χώρου είναι ένα pixel της εικόνας) και την κλίση του.
class FloorPlanState {
  const FloorPlanState({
    required this.floorId,
    this.isActive = false,
    this.patternHash,
    this.cmPerPixel = 1,
    this.patternCenter = Offset.zero,
    this.patternRotationDegrees = 0,
    this.patternOpacity = 0.5,
    this.patternHidden = false,
    this.patternCalibrated = false,
  });

  final int floorId;
  final bool isActive;

  /// Το αποτύπωμα της εικόνας του πατρόν· `null` όταν δεν έχει φορτωθεί.
  final String? patternHash;
  final double cmPerPixel;
  final Offset patternCenter;
  final double patternRotationDegrees;
  final double patternOpacity;
  final bool patternHidden;

  /// Έχει γίνει βαθμονόμηση με πραγματική μέτρηση. Ως τότε τα μήκη που
  /// δείχνει ο χάρτης δεν αντιστοιχούν σε μέτρα.
  final bool patternCalibrated;

  bool get hasPattern => patternHash != null;

  /// Οι στήλες που διαβάζονται — ρητά, ώστε η εικόνα να μην ταξιδεύει ποτέ
  /// μαζί με την κατάσταση.
  static const List<String> columns = [
    'floor_id',
    'is_active',
    'pattern_hash',
    'pattern_cm_per_px',
    'pattern_center_x',
    'pattern_center_y',
    'pattern_rotation_degrees',
    'pattern_opacity',
    'pattern_hidden',
    'pattern_calibrated',
  ];

  factory FloorPlanState.fromMap(Map<String, Object?> row) {
    double d(String key, double fallback) =>
        (row[key] as num?)?.toDouble() ?? fallback;
    final cmPerPixel = d('pattern_cm_per_px', 1);
    return FloorPlanState(
      floorId: row['floor_id'] as int,
      isActive: (row['is_active'] as int? ?? 0) == 1,
      patternHash: row['pattern_hash'] as String?,
      cmPerPixel: cmPerPixel > 0 ? cmPerPixel : 1,
      patternCenter: Offset(d('pattern_center_x', 0), d('pattern_center_y', 0)),
      patternRotationDegrees: d('pattern_rotation_degrees', 0),
      patternOpacity: d('pattern_opacity', 0.5).clamp(0.0, 1.0),
      patternHidden: (row['pattern_hidden'] as int? ?? 0) == 1,
      patternCalibrated: (row['pattern_calibrated'] as int? ?? 0) == 1,
    );
  }

  /// Μόνο οι στήλες τοποθέτησης του πατρόν — ό,τι αλλάζει με μετακίνηση,
  /// περιστροφή, διαφάνεια ή βαθμονόμηση.
  Map<String, Object?> patternPlacementMap() => {
    'pattern_cm_per_px': cmPerPixel,
    'pattern_center_x': patternCenter.dx,
    'pattern_center_y': patternCenter.dy,
    'pattern_rotation_degrees': patternRotationDegrees,
    'pattern_opacity': patternOpacity,
    'pattern_hidden': patternHidden ? 1 : 0,
    'pattern_calibrated': patternCalibrated ? 1 : 0,
  };

  FloorPlanState copyWith({
    String? patternHash,
    bool clearPattern = false,
    double? cmPerPixel,
    Offset? patternCenter,
    double? patternRotationDegrees,
    double? patternOpacity,
    bool? patternHidden,
    bool? patternCalibrated,
  }) => FloorPlanState(
    floorId: floorId,
    isActive: isActive,
    patternHash: clearPattern ? null : patternHash ?? this.patternHash,
    cmPerPixel: cmPerPixel ?? this.cmPerPixel,
    patternCenter: patternCenter ?? this.patternCenter,
    patternRotationDegrees:
        patternRotationDegrees ?? this.patternRotationDegrees,
    patternOpacity: patternOpacity ?? this.patternOpacity,
    patternHidden: patternHidden ?? this.patternHidden,
    patternCalibrated: patternCalibrated ?? this.patternCalibrated,
  );
}
