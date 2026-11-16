import '../../../../../core/database/database_helper.dart';
import '../../../../../core/services/profile_settings.dart';
import '../floor_plan_editor_controller.dart';

/// Το εργαλείο με το οποίο ξανανοίγει η σχεδίαση: το τελευταίο **μόνιμο**
/// εργαλείο του χρήστη, και για το «Αντικείμενο» το είδος του.
class FloorPlanRememberedTool {
  const FloorPlanRememberedTool(this.tool, {this.objectKindId});

  final FloorPlanTool tool;

  /// Μόνο για το [FloorPlanTool.object].
  final int? objectKindId;

  /// Στιγμιαία εργαλεία: τελειώνουν με τη δουλειά τους και δεν έχει νόημα να
  /// ξανανοίξει η σχεδίαση με αυτά.
  static const Set<FloorPlanTool> transient = {
    FloorPlanTool.calibrate,
    FloorPlanTool.movePattern,
    FloorPlanTool.measure,
  };

  /// Αυτό που θα αποθηκευτεί για το εργαλείο [tool]· `null` για στιγμιαίο
  /// εργαλείο, ώστε να μείνει το προηγούμενο.
  static String? encode(FloorPlanTool tool, {int? objectKindId}) {
    if (transient.contains(tool)) return null;
    if (tool == FloorPlanTool.object) {
      return objectKindId == null ? null : 'object:$objectKindId';
    }
    return tool.name;
  }

  /// `null` όταν δεν έχει αποθηκευτεί τίποτα ή η τιμή δεν διαβάζεται.
  static FloorPlanRememberedTool? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('object:')) {
      final id = int.tryParse(raw.substring('object:'.length));
      if (id == null) return null;
      return FloorPlanRememberedTool(FloorPlanTool.object, objectKindId: id);
    }
    for (final tool in FloorPlanTool.values) {
      if (tool.name == raw && !transient.contains(tool)) {
        if (tool == FloorPlanTool.object) return null;
        return FloorPlanRememberedTool(tool);
      }
    }
    return null;
  }
}

/// Το τελευταίο εργαλείο σχεδίασης του ενεργού χρήστη — προσωπική ρύθμιση,
/// μία για όλους τους ορόφους.
class FloorPlanToolPreference {
  const FloorPlanToolPreference._();

  static const _key = ProfileSettingKeys.floorPlanLastTool;

  static Future<FloorPlanRememberedTool?> read() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final raw = await ProfileSettings(db, setting: _key).read(_key);
      return FloorPlanRememberedTool.decode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String encoded) async {
    final db = await DatabaseHelper.instance.database;
    await ProfileSettings(db, setting: _key).write(_key, encoded);
  }
}
