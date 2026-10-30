import '../../../../../core/models/floor_plan_element.dart';
import '../../../models/department_model.dart';
import '../../../screens/widgets/department_color_palette.dart';
import 'floor_plan_painter.dart';

/// Οι χώροι όπως τους ζωγραφίζει ο καμβάς: όνομα τμήματος ή ελεύθερο όνομα,
/// και το χρώμα του τμήματος. Κοινό για τη σχεδίαση, την προβολή του χάρτη
/// και τον μικρό χάρτη των κλήσεων.
List<FloorPlanRoomView> buildFloorPlanRoomViews(
  Iterable<FloorPlanElement> elements,
  Map<int, DepartmentModel> departments,
) => [
  for (final room in elements)
    if (room.kind == FloorPlanElementKind.room && room.points.length >= 3)
      FloorPlanRoomView(
        id: room.id,
        corners: room.points,
        label: floorPlanRoomLabel(room, departments),
        color: tryParseDepartmentHex(departments[room.departmentId]?.color),
        labelOffset: room.labelOffset,
        labelSizeCm: room.fontSize ?? kFloorPlanDefaultRoomLabelSizeCm,
      ),
];

String floorPlanRoomLabel(
  FloorPlanElement room,
  Map<int, DepartmentModel> departments,
) {
  final departmentId = room.departmentId;
  if (departmentId == null) return room.name ?? '';
  // Το τμήμα διαγράφηκε ή έγινε εταιρεία μετά τη σχεδίαση.
  return departments[departmentId]?.name ?? 'Τμήμα εκτός Καταλόγου';
}
