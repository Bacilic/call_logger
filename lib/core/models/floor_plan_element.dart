import 'dart:convert';
import 'dart:ui' show Offset;

/// Το είδος ενός στοιχείου του σχεδιασμένου χάρτη.
///
/// Η τιμή [key] είναι αυτή που γράφεται στη βάση· δεν αλλάζει ποτέ, ακόμη κι
/// αν αλλάξει το όνομα της τιμής στον κώδικα.
enum FloorPlanElementKind {
  wall('wall'),

  /// Κενό σε τοίχο (πόρτα). Δεν ζει μόνο του: ανήκει στον τοίχο του.
  opening('opening'),

  /// Χώρος με όνομα: τμήμα του Καταλόγου ή ελεύθερο όνομα (διάδρομος,
  /// αποθήκη). Τα σημεία του είναι οι γωνίες του.
  room('room'),

  /// Ελεύθερο κείμενο: ένα σημείο (το κέντρο του), το κείμενο στο `name`,
  /// μέγεθος σε εκατοστά και κλίση. Γυρίζει μαζί με το σχέδιο.
  text('text'),

  /// Γραμμή διάστασης: τα δύο άκρα που μετρά και ένα τρίτο σημείο που ορίζει
  /// πόσο απέχει η γραμμή από το αντικείμενο.
  dimension('dimension');

  const FloorPlanElementKind(this.key);

  final String key;

  static FloorPlanElementKind? fromKey(String? key) {
    for (final kind in values) {
      if (kind.key == key) return kind;
    }
    return null;
  }
}

/// Το μέγεθος γραμμάτων ενός νέου κειμένου, σε εκατοστά πραγματικού χώρου.
const double kFloorPlanDefaultTextSizeCm = 40;

/// Το μέγεθος γραμμάτων του ονόματος ενός χώρου όταν δεν έχει αλλάξει με
/// A− / A+, σε εκατοστά πραγματικού χώρου.
const double kFloorPlanDefaultRoomLabelSizeCm = 50;

/// Ένα στοιχείο του σχεδιασμένου χάρτη, όπως ζει στη βάση.
///
/// Τα [points] είναι σε **εκατοστά πραγματικού χώρου**. Στον τοίχο είναι η αρχή
/// και το τέλος του. Στο άνοιγμα είναι αποστάσεις κατά μήκος του τοίχου
/// [parentId] (μόνο το `dx` μετρά): έτσι ακολουθεί τον τοίχο όπου κι αν πάει.
class FloorPlanElement {
  const FloorPlanElement({
    required this.id,
    required this.floorId,
    required this.kind,
    required this.points,
    this.parentId,
    this.name,
    this.departmentId,
    this.fontSize,
    this.rotationDegrees = 0,
    this.labelOffset,
  });

  final int id;
  final int floorId;
  final FloorPlanElementKind kind;
  final List<Offset> points;
  final int? parentId;

  /// Ελεύθερο όνομα χώρου, ή το περιεχόμενο ενός κειμένου· `null` όταν ο
  /// χώρος είναι τμήμα.
  final String? name;

  /// Το τμήμα του Καταλόγου που είναι ο χώρος· `null` για ελεύθερο όνομα.
  final int? departmentId;

  /// Μέγεθος γραμμάτων του κειμένου, σε εκατοστά.
  final double? fontSize;

  /// Κλίση του κειμένου ως προς το σχέδιο.
  final double rotationDegrees;

  /// Χώρος: πόσο έχει μετακινηθεί το όνομά του από το κέντρο του χώρου, σε
  /// εκατοστά· `null` = στο κέντρο. Σχετική θέση, ώστε το όνομα να ακολουθεί
  /// τον χώρο όταν μετακινείται.
  final Offset? labelOffset;

  /// `null` όταν η γραμμή είναι είδους που δεν ξέρει αυτή η έκδοση — ένα
  /// επόμενο βήμα του χάρτη μπορεί να έχει γράψει ήδη αντικείμενα.
  static FloorPlanElement? fromMap(Map<String, Object?> row) {
    final kind = FloorPlanElementKind.fromKey(row['kind'] as String?);
    if (kind == null) return null;
    final points = decodeFloorPlanPoints(row['points_json'] as String?);
    if (points == null) return null;
    return FloorPlanElement(
      id: row['id'] as int,
      floorId: row['floor_id'] as int,
      kind: kind,
      points: points,
      parentId: row['parent_id'] as int?,
      name: row['name'] as String?,
      departmentId: row['department_id'] as int?,
      fontSize: (row['font_size'] as num?)?.toDouble(),
      rotationDegrees: (row['rotation_degrees'] as num?)?.toDouble() ?? 0,
      labelOffset: _offsetOrNull(row['label_dx'], row['label_dy']),
    );
  }

  static Offset? _offsetOrNull(Object? dx, Object? dy) =>
      dx is num && dy is num ? Offset(dx.toDouble(), dy.toDouble()) : null;

  /// Οι στήλες που διαβάζονται για κάθε στοιχείο.
  static const List<String> columns = [
    'id',
    'floor_id',
    'kind',
    'points_json',
    'parent_id',
    'name',
    'department_id',
    'font_size',
    'rotation_degrees',
    'label_dx',
    'label_dy',
  ];

  Map<String, Object?> toInsertMap() => {
    'floor_id': floorId,
    'kind': kind.key,
    'points_json': encodeFloorPlanPoints(points),
    'parent_id': parentId,
    'name': name,
    'department_id': departmentId,
    'font_size': fontSize,
    'rotation_degrees': rotationDegrees,
    'label_dx': labelOffset == null ? null : _round(labelOffset!.dx),
    'label_dy': labelOffset == null ? null : _round(labelOffset!.dy),
  };

  FloorPlanElement copyWith({
    int? id,
    int? parentId,
    List<Offset>? points,
    String? name,
    double? fontSize,
    double? rotationDegrees,
    Offset? labelOffset,
    bool labelToCenter = false,
  }) => FloorPlanElement(
    id: id ?? this.id,
    floorId: floorId,
    kind: kind,
    points: points ?? this.points,
    parentId: parentId ?? this.parentId,
    name: name ?? this.name,
    departmentId: departmentId,
    fontSize: fontSize ?? this.fontSize,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    labelOffset: labelToCenter ? null : labelOffset ?? this.labelOffset,
  );

  /// Ίδιος χώρος με άλλη ταυτότητα: τμήμα **ή** ελεύθερο όνομα, ποτέ και τα δύο.
  FloorPlanElement withRoomIdentity({String? name, int? departmentId}) =>
      FloorPlanElement(
        id: id,
        floorId: floorId,
        kind: kind,
        points: points,
        parentId: parentId,
        name: departmentId == null ? name : null,
        departmentId: departmentId,
        fontSize: fontSize,
        rotationDegrees: rotationDegrees,
        labelOffset: labelOffset,
      );
}

/// Τα σημεία ως `[[x, y], …]`, στρογγυλεμένα στο χιλιοστό — η ακρίβεια
/// πάνω από αυτό είναι θόρυβος και φουσκώνει μόνο το κείμενο.
String encodeFloorPlanPoints(List<Offset> points) => jsonEncode([
  for (final p in points) [_round(p.dx), _round(p.dy)],
]);

List<Offset>? decodeFloorPlanPoints(String? raw) {
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final points = <Offset>[];
    for (final item in decoded) {
      if (item is! List || item.length < 2) return null;
      final x = item[0];
      final y = item[1];
      if (x is! num || y is! num) return null;
      points.add(Offset(x.toDouble(), y.toDouble()));
    }
    return points;
  } on FormatException {
    return null;
  }
}

double _round(double v) => (v * 10).roundToDouble() / 10;
