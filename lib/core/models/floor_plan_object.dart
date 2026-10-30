import 'dart:ui' show Offset, Size;

/// Ένα αντικείμενο του νέου χάρτη (εκτυπωτής, γραφείο…), όπως ζει στη βάση.
///
/// Θέση ([center]) και μέγεθος ([size]) σε **εκατοστά πραγματικού χώρου**,
/// όπως τα στοιχεία σχεδίου. Το [size] υπάρχει μόνο για όσα σχεδιάζονται ως
/// παραλληλόγραμμο (έπιπλα, καμπίνες)· τα υπόλοιπα είναι σύμβολα σταθερού
/// μεγέθους.
///
/// Ό,τι είναι μέσα σε καμπίνα ([cabinetId]) δεν ζωγραφίζεται στον χάρτη: ζει
/// στη θέση [rackU] (από πάνω) και πιάνει [rackUnits] U. Για την ίδια την
/// καμπίνα το [rackUnits] είναι πόσα U έχει.
class FloorPlanObject {
  const FloorPlanObject({
    required this.id,
    required this.floorId,
    required this.kindId,
    required this.center,
    this.size,
    this.rotationDegrees = 0,
    this.name,
    this.ip,
    this.lansweeperName,
    this.notes,
    this.cabinetId,
    this.rackU,
    this.rackUnits,
    this.stackId,
    this.stackUnit,
  });

  final int id;
  final int floorId;
  final int kindId;
  final Offset center;
  final Size? size;
  final double rotationDegrees;
  final String? name;
  final String? ip;
  final String? lansweeperName;
  final String? notes;
  final int? cabinetId;
  final int? rackU;
  final int? rackUnits;
  final int? stackId;
  final int? stackUnit;

  /// Είναι μέσα σε καμπίνα — άρα όχι στον χάρτη.
  bool get inCabinet => cabinetId != null;

  /// Πόσα U πιάνει μέσα στην καμπίνα· 1 όταν δεν έχει δηλωθεί.
  int get heightU => rackUnits ?? 1;

  static const List<String> columns = [
    'id',
    'floor_id',
    'kind_id',
    'x',
    'y',
    'width',
    'height',
    'rotation_degrees',
    'name',
    'ip',
    'lansweeper_name',
    'notes',
    'cabinet_id',
    'rack_u',
    'rack_units',
    'stack_id',
    'stack_unit',
  ];

  factory FloorPlanObject.fromMap(Map<String, Object?> row) {
    final width = (row['width'] as num?)?.toDouble();
    final height = (row['height'] as num?)?.toDouble();
    return FloorPlanObject(
      id: row['id'] as int,
      floorId: row['floor_id'] as int,
      kindId: row['kind_id'] as int,
      center: Offset(
        (row['x'] as num).toDouble(),
        (row['y'] as num).toDouble(),
      ),
      size: width != null && height != null ? Size(width, height) : null,
      rotationDegrees: (row['rotation_degrees'] as num?)?.toDouble() ?? 0,
      name: row['name'] as String?,
      ip: row['ip'] as String?,
      lansweeperName: row['lansweeper_name'] as String?,
      notes: row['notes'] as String?,
      cabinetId: row['cabinet_id'] as int?,
      rackU: row['rack_u'] as int?,
      rackUnits: row['rack_units'] as int?,
      stackId: row['stack_id'] as int?,
      stackUnit: row['stack_unit'] as int?,
    );
  }

  Map<String, Object?> toInsertMap() => {
    'floor_id': floorId,
    'kind_id': kindId,
    'x': _round(center.dx),
    'y': _round(center.dy),
    'width': size == null ? null : _round(size!.width),
    'height': size == null ? null : _round(size!.height),
    'rotation_degrees': rotationDegrees,
    'name': name,
    'ip': ip,
    'lansweeper_name': lansweeperName,
    'notes': notes,
    'cabinet_id': cabinetId,
    'rack_u': rackU,
    'rack_units': rackUnits,
    'stack_id': stackId,
    'stack_unit': stackUnit,
  };

  FloorPlanObject copyWith({
    int? id,
    Offset? center,
    Size? size,
    double? rotationDegrees,
  }) => FloorPlanObject(
    id: id ?? this.id,
    floorId: floorId,
    kindId: kindId,
    center: center ?? this.center,
    size: size ?? this.size,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    name: name,
    ip: ip,
    lansweeperName: lansweeperName,
    notes: notes,
    cabinetId: cabinetId,
    rackU: rackU,
    rackUnits: rackUnits,
    stackId: stackId,
    stackUnit: stackUnit,
  );

  /// Ίδιο αντικείμενο σε άλλη θέση καμπίνας. Όλα ρητά, ώστε `null` να
  /// σημαίνει «όχι σε καμπίνα» και όχι «όπως ήταν».
  FloorPlanObject withRack({
    required int? cabinetId,
    required int? rackU,
    required int? rackUnits,
    Offset? center,
  }) => FloorPlanObject(
    id: id,
    floorId: floorId,
    kindId: kindId,
    center: center ?? this.center,
    size: size,
    rotationDegrees: rotationDegrees,
    name: name,
    ip: ip,
    lansweeperName: lansweeperName,
    notes: notes,
    cabinetId: cabinetId,
    rackU: rackU,
    rackUnits: rackUnits,
    stackId: stackId,
    stackUnit: stackUnit,
  );

  /// Ίδιο αντικείμενο με άλλα στοιχεία. Κενό κείμενο γίνεται `null`.
  FloorPlanObject withDetails({
    String? name,
    String? ip,
    String? lansweeperName,
    String? notes,
  }) => FloorPlanObject(
    id: id,
    floorId: floorId,
    kindId: kindId,
    center: center,
    size: size,
    rotationDegrees: rotationDegrees,
    name: _blankToNull(name),
    ip: _blankToNull(ip),
    lansweeperName: _blankToNull(lansweeperName),
    notes: _blankToNull(notes),
    cabinetId: cabinetId,
    rackU: rackU,
    rackUnits: rackUnits,
    stackId: stackId,
    stackUnit: stackUnit,
  );

  /// Ίδια θέση, μέγεθος και κλίση με το [other] — και ίδια θέση καμπίνας.
  bool samePlaceAs(FloorPlanObject other) =>
      center == other.center &&
      size == other.size &&
      rotationDegrees == other.rotationDegrees &&
      cabinetId == other.cabinetId &&
      rackU == other.rackU &&
      rackUnits == other.rackUnits;

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Στρογγύλεμα στο χιλιοστό, όπως τα σημεία των στοιχείων σχεδίου.
  static double _round(double v) => (v * 10).roundToDouble() / 10;
}
