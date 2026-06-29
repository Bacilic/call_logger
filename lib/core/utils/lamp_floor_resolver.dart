import '../models/building_map_floor.dart';
import 'search_text_normalizer.dart';

/// Αντιστοίχιση ιστορικού κειμένου ορόφου Λάμπας σε `building_map_floors.id`.
class LampFloorResolver {
  LampFloorResolver._();

  static int? resolveFloorId({
    required String levelText,
    required List<BuildingMapFloor> floors,
  }) {
    final levelKey = SearchTextNormalizer.normalizeForSearch(levelText.trim());
    if (levelKey.isEmpty) return null;

    for (final floor in floors) {
      final labelKey = SearchTextNormalizer.normalizeForSearch(floor.label);
      if (labelKey.isEmpty) continue;
      if (labelKey == levelKey || labelKey.startsWith(levelKey)) {
        return floor.id;
      }
    }
    return null;
  }

  static String? unmatchedLevelWarning(String levelText) {
    final trimmed = levelText.trim();
    if (trimmed.isEmpty) return null;
    return 'Ο όροφος "$trimmed" δεν αντιστοιχίστηκε σε φύλλο χάρτη';
  }
}
