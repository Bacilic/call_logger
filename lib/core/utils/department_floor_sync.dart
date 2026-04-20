/// Βοηθητική λογική συγχρονισμού `floor_id` ↔ `map_floor` για τμήματα.
class DepartmentFloorSync {
  DepartmentFloorSync._();

  /// Επιλύει ποιος όροφος (φύλλο κατόψης) ισχύει: το σχέδιο στον χάρτη κερδίζει το χειροκίνητο.
  static int? resolveEffectiveFloorId({
    int? drawingFloorId,
    int? manualFloorId,
  }) {
    if (drawingFloorId != null) return drawingFloorId;
    if (manualFloorId != null) return manualFloorId;
    return null;
  }

  /// Ενσωματώνει στο map ενημέρωσης το `floor_id` και συγχρονίζει το `map_floor`
  /// ως `floorId.toString()` όταν υπάρχει τελικός όροφος.
  static Map<String, dynamic> mergeFloorContext(
    Map<String, dynamic> updates, {
    int? drawingFloorId,
    int? manualFloorId,
  }) {
    final out = Map<String, dynamic>.from(updates);
    final fid = resolveEffectiveFloorId(
      drawingFloorId: drawingFloorId,
      manualFloorId: manualFloorId,
    );
    if (fid != null) {
      out['floor_id'] = fid;
      out['map_floor'] = fid.toString();
    }
    return out;
  }
}
