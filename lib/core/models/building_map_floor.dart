/// Φύλλο κάτοψης για τον χάρτη κτιρίου (`building_map_floors`).
class BuildingMapFloor {
  BuildingMapFloor({
    required this.id,
    required this.sortOrder,
    required this.label,
    this.floorGroup,
    required this.imagePath,
    required this.rotationDegrees,
    this.imageHash,
    this.hasPreviousImage = false,
  });

  final int id;
  final int sortOrder;
  final String label;
  final String? floorGroup;

  /// Το όνομα της **παλιάς, τοπικής** εικόνας του σταθμού (`maps_images/…`).
  ///
  /// Δεν δείχνεται πουθενά: χρησιμεύει μόνο στο «Ανέβασμα κατόψεων στη βάση»,
  /// για να βρει ο σταθμός του διαχειριστή ποιο αρχείο του ανήκει σε ποιον όροφο.
  final String imagePath;
  final double rotationDegrees;

  /// Το αποτύπωμα της εικόνας που είναι αποθηκευμένη στη βάση· `null` όταν η
  /// κάτοψη δεν έχει ανέβει ακόμη.
  final String? imageHash;

  /// Υπάρχει προηγούμενη εικόνα για «Επαναφορά προηγούμενης κάτοψης».
  final bool hasPreviousImage;

  /// Η κάτοψη έχει ανέβει στη βάση και μπορεί να δειχθεί.
  bool get hasImage => imageHash != null;

  factory BuildingMapFloor.fromMap(Map<String, dynamic> row) {
    final hash = (row['image_hash'] as String?)?.trim();
    return BuildingMapFloor(
      id: row['id'] as int,
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      label: (row['label'] as String?) ?? '',
      floorGroup: row['floor_group'] as String?,
      imagePath: (row['image_path'] as String?) ?? '',
      rotationDegrees: (row['rotation_degrees'] as num?)?.toDouble() ?? 0,
      imageHash: hash == null || hash.isEmpty ? null : hash,
      hasPreviousImage: (row['previous_image_hash'] as String?) != null,
    );
  }
}
