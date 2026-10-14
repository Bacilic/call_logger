import '../../../../core/models/building_map_floor.dart';
import '../../models/department_model.dart';
import 'building_map_floor_ordering.dart';

/// Πού πηγαίνει ο χάρτης όταν η αναζήτηση βρει τμήμα.
class BuildingMapJumpFallback {
  const BuildingMapJumpFallback._({
    required this.isMapped,
    this.fallbackFloorId,
    this.message,
  });

  /// Το τμήμα έχει θέση σε υπαρκτό φύλλο — μετάβαση εκεί, χωρίς μήνυμα.
  final bool isMapped;

  /// Το φύλλο που ανοίγει όταν το τμήμα δεν έχει θέση. `null` όταν δεν
  /// υπάρχει κανένα φύλλο να ανοίξει.
  final int? fallbackFloorId;

  /// Η εξήγηση που βλέπει ο χρήστης στη θέση του τμήματος που λείπει.
  final String? message;
}

/// Συμβόλαιο: η αναζήτηση δεν αφήνει ποτέ τον χρήστη χωρίς απάντηση — ή δείχνει
/// το τμήμα, ή ανοίγει τον πιθανότερο όροφο και λέει γιατί δεν το βλέπει.
/// Σειρά: όροφος της φόρμας τμήματος, μετά το φύλλο της (ορφανής) θέσης, μετά
/// το πρώτο φύλλο.
BuildingMapJumpFallback resolveBuildingMapJumpFallback({
  required DepartmentModel department,
  required List<BuildingMapFloor> floors,
}) {
  final mapFloor = department.mapFloor?.trim();
  final mappedFloorId = mapFloor == null ? null : int.tryParse(mapFloor);
  final isMapped =
      department.mapX != null &&
      department.mapY != null &&
      (department.mapWidth ?? 0) > 0 &&
      (department.mapHeight ?? 0) > 0 &&
      mappedFloorId != null &&
      floors.any((f) => f.id == mappedFloorId);

  if (isMapped) {
    return const BuildingMapJumpFallback._(isMapped: true);
  }

  int? fallbackFloorId;
  final preferredFloorId = department.floorId;
  if (preferredFloorId != null && floors.any((f) => f.id == preferredFloorId)) {
    fallbackFloorId = preferredFloorId;
  } else if (mappedFloorId != null &&
      floors.any((f) => f.id == mappedFloorId)) {
    fallbackFloorId = mappedFloorId;
  } else if (floors.isNotEmpty) {
    fallbackFloorId = floors.first.id;
  }
  if (fallbackFloorId == null) {
    return const BuildingMapJumpFallback._(isMapped: false);
  }

  BuildingMapFloor? fallbackFloor;
  for (final f in floors) {
    if (f.id == fallbackFloorId) {
      fallbackFloor = f;
      break;
    }
  }
  final deptName = department.displayName;
  final String message;
  if (preferredFloorId != null &&
      fallbackFloorId == preferredFloorId &&
      fallbackFloor != null) {
    message =
        'Το τμήμα «$deptName» βρίσκεται στον όροφο '
        '«${buildingMapFloorDisplayLabel(fallbackFloor)}», αλλά δεν έχει '
        'σχεδιαστεί ακόμα στον χάρτη.';
  } else {
    message = 'Το τμήμα «$deptName» δεν έχει καταχωρημένη θέση στον χάρτη.';
  }
  return BuildingMapJumpFallback._(
    isMapped: false,
    fallbackFloorId: fallbackFloorId,
    message: message,
  );
}
