import 'dart:ui' show Offset;

/// Τι τοποθετείται από τον Κατάλογο. Η τιμή [key] γράφεται στη βάση και δεν
/// αλλάζει ποτέ.
enum FloorPlanPlacementType {
  /// Ο υπάλληλος μπορεί να έχει **πολλές** θέσεις (δουλεύει σε δύο γραφεία).
  user('user'),

  /// Το τηλέφωνο έχει το πολύ μία θέση.
  phone('phone'),

  /// Ο εξοπλισμός έχει το πολύ μία θέση.
  equipment('equipment');

  const FloorPlanPlacementType(this.key);

  final String key;

  /// Το πολύ μία θέση στον χάρτη — δεύτερη σημαίνει μεταφορά.
  bool get single => this != user;

  static FloorPlanPlacementType? fromKey(String? key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// Η θέση μιας εγγραφής του Καταλόγου στον χάρτη. Ο χάρτης κρατά **μόνο** τη
/// θέση· όνομα, αριθμός και κωδικός διαβάζονται πάντα από τον Κατάλογο.
class FloorPlanPlacement {
  const FloorPlanPlacement({
    required this.id,
    required this.type,
    required this.entityId,
    required this.floorId,
    required this.center,
    this.rotationDegrees = 0,
  });

  final int id;
  final FloorPlanPlacementType type;
  final int entityId;
  final int floorId;
  final Offset center;

  /// Η κλίση του συμβόλου· η ετικέτα μένει πάντα όρθια.
  final double rotationDegrees;

  static const List<String> columns = [
    'id',
    'entity_type',
    'entity_id',
    'floor_id',
    'x',
    'y',
    'rotation_degrees',
  ];

  /// `null` όταν ο τύπος γράφτηκε από νεότερη έκδοση της εφαρμογής.
  static FloorPlanPlacement? fromMap(Map<String, Object?> row) {
    final type = FloorPlanPlacementType.fromKey(row['entity_type'] as String?);
    if (type == null) return null;
    return FloorPlanPlacement(
      id: row['id'] as int,
      type: type,
      entityId: row['entity_id'] as int,
      floorId: row['floor_id'] as int,
      center: Offset(
        (row['x'] as num).toDouble(),
        (row['y'] as num).toDouble(),
      ),
      rotationDegrees: (row['rotation_degrees'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, Object?> toInsertMap() => {
    'entity_type': type.key,
    'entity_id': entityId,
    'floor_id': floorId,
    'x': (center.dx * 10).roundToDouble() / 10,
    'y': (center.dy * 10).roundToDouble() / 10,
    'rotation_degrees': rotationDegrees,
  };

  FloorPlanPlacement copyWith({
    int? id,
    int? floorId,
    Offset? center,
    double? rotationDegrees,
  }) => FloorPlanPlacement(
    id: id ?? this.id,
    type: type,
    entityId: entityId,
    floorId: floorId ?? this.floorId,
    center: center ?? this.center,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
  );
}

/// Μία εγγραφή του Καταλόγου όπως τη χρειάζεται ο χάρτης: τι δείχνει η
/// ετικέτα της και σε ποια τμήματα ανήκει (για την προειδοποίηση διαφωνίας).
class FloorPlanCatalogEntry {
  const FloorPlanCatalogEntry({
    required this.type,
    required this.entityId,
    required this.label,
    this.departmentIds = const {},
    this.phones = const [],
    this.equipment = const [],
    this.holders = const [],
    this.lansweeperName,
  });

  final FloorPlanPlacementType type;
  final int entityId;

  /// Υπάλληλος: επώνυμο και όνομα· τηλέφωνο: αριθμός· εξοπλισμός: κωδικός.
  final String label;

  /// Το τηλέφωνο μπορεί να ανήκει σε περισσότερα τμήματα.
  final Set<int> departmentIds;

  /// Υπάλληλος: οι αριθμοί των τηλεφώνων του.
  final List<String> phones;

  /// Υπάλληλος: οι κωδικοί του εξοπλισμού που χρησιμοποιεί.
  final List<String> equipment;

  /// Τηλέφωνο: ποιοι το έχουν· εξοπλισμός: ποιοι τον χρησιμοποιούν.
  final List<String> holders;

  /// Εξοπλισμός: το όνομά του στο Lansweeper.
  final String? lansweeperName;

  (FloorPlanPlacementType, int) get key => (type, entityId);
}
