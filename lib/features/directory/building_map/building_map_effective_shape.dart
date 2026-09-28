import '../models/department_model.dart';
import 'building_map_label_layout.dart';
import 'providers/building_map_providers.dart';

/// Η γεωμετρία με την οποία ζωγραφίζεται ΤΩΡΑ ένα τμήμα στο φύλλο: είτε το
/// ενεργό προσχέδιο (όσο ο χρήστης το ορίζει ή το επεξεργάζεται) είτε η
/// αποθηκευμένη θέση του τμήματος.
///
/// Συμβόλαιο: όσο υπάρχει ενεργό προσχέδιο για το επιλεγμένο τμήμα, το
/// προσχέδιο κυβερνά — σε ΚΑΘΕ εργαλείο που παράγει προσχέδιο (Σχεδίαση και
/// Επεξεργασία) και ανεξάρτητα από το αν το τμήμα έχει ήδη αποθηκευμένη θέση
/// στο φύλλο. Ένα τμήμα που σχεδιάζεται για πρώτη φορά δεν έχει ακόμη
/// `map_floor`, γι' αυτό το προσχέδιο παρακάμπτει και το φίλτρο φύλλου.
class MapDepartmentShapeResolution {
  const MapDepartmentShapeResolution({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotation,
    required this.labelOffsetX,
    required this.labelOffsetY,
    required this.anchorOffsetX,
    required this.anchorOffsetY,
    required this.labelFontScale,
    required this.labelWidth,
    required this.labelHeight,
    required this.isDraftGoverned,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final double? labelOffsetX;
  final double? labelOffsetY;
  final double? anchorOffsetX;
  final double? anchorOffsetY;
  final double labelFontScale;
  final double labelWidth;
  final double labelHeight;

  /// True όταν οι τιμές προέρχονται από το προσχέδιο και όχι από τη βάση.
  final bool isDraftGoverned;
}

/// True όταν το προσχέδιο κυβερνά τη γεωμετρία αυτού του τμήματος.
bool draftGovernsDepartment({
  required DepartmentModel dep,
  required DraftDepartmentShape? draftShape,
  required MapToolMode toolMode,
  required int? highlightDepartmentId,
}) {
  if (draftShape == null) return false;
  if (highlightDepartmentId == null) return false;
  if (dep.id != highlightDepartmentId) return false;
  return toolMode == MapToolMode.draw || toolMode == MapToolMode.edit;
}

/// Επιστρέφει null όταν το τμήμα δεν σχεδιάζεται σε αυτό το φύλλο ή του λείπει
/// γεωμετρία (ούτε προσχέδιο ούτε αποθηκευμένη θέση).
MapDepartmentShapeResolution? resolveMapDepartmentShape({
  required DepartmentModel dep,
  required String sheetIdString,
  required DraftDepartmentShape? draftShape,
  required MapToolMode toolMode,
  required int? highlightDepartmentId,
}) {
  final draftGoverns = draftGovernsDepartment(
    dep: dep,
    draftShape: draftShape,
    toolMode: toolMode,
    highlightDepartmentId: highlightDepartmentId,
  );

  // Το φίλτρο φύλλου δεν ισχύει για το τμήμα υπό σχεδίαση: η θέση του στο
  // φύλλο γράφεται μόνο με την Επιβεβαίωση (✓).
  if (!draftGoverns && (dep.mapFloor ?? '') != sheetIdString) return null;

  if (draftGoverns) {
    final draft = draftShape!;
    if (draft.width <= 0 || draft.height <= 0) return null;
    return MapDepartmentShapeResolution(
      x: draft.x,
      y: draft.y,
      width: draft.width,
      height: draft.height,
      rotation: draft.rotation,
      labelOffsetX: draft.labelOffsetX,
      labelOffsetY: draft.labelOffsetY,
      anchorOffsetX: draft.anchorOffsetX,
      anchorOffsetY: draft.anchorOffsetY,
      labelFontScale: draft.labelFontScale,
      labelWidth: draft.labelWidth,
      labelHeight: draft.labelHeight,
      isDraftGoverned: true,
    );
  }

  final nx = dep.mapX;
  final ny = dep.mapY;
  final nw = dep.mapWidth;
  final nh = dep.mapHeight;
  if (nx == null || ny == null || nw == null || nh == null) return null;
  if (nw <= 0 || nh <= 0) return null;

  return MapDepartmentShapeResolution(
    x: nx,
    y: ny,
    width: nw,
    height: nh,
    rotation: dep.mapRotation,
    labelOffsetX: dep.mapLabelOffsetX,
    labelOffsetY: dep.mapLabelOffsetY,
    anchorOffsetX: dep.mapAnchorOffsetX,
    anchorOffsetY: dep.mapAnchorOffsetY,
    labelFontScale: effectiveMapLabelFontScale(dep.mapLabelFontScale),
    labelWidth: effectiveMapLabelWidth(dep.mapLabelWidth),
    labelHeight: effectiveMapLabelHeight(dep.mapLabelHeight),
    isDraftGoverned: false,
  );
}
