import 'dart:ui' show Offset;

import '../../../../core/models/floor_plan_element.dart';
import '../../../../core/models/floor_plan_object.dart';
import '../../../../core/models/floor_plan_object_kind.dart';
import '../../../../core/models/floor_plan_placement.dart';
import '../../../../core/models/floor_plan_port.dart';
import 'floor_plan_objects.dart';
import 'floor_plan_rooms.dart';

/// «Ποιος χώρος είναι εδώ;» για τα στοιχεία [elements] ενός ορόφου: ο
/// μικρότερος χώρος που περιέχει το σημείο, με το τμήμα του ή το ελεύθερο
/// όνομά του.
({int? departmentId, String? name})? Function(Offset world) floorPlanRoomLookup(
  List<FloorPlanElement> elements,
) {
  final rooms = [
    for (final e in elements)
      if (e.kind == FloorPlanElementKind.room && e.points.length >= 3) e,
  ];
  return (world) {
    FloorPlanElement? best;
    var area = double.infinity;
    for (final room in rooms) {
      if (!polygonContains(room.points, world)) continue;
      final a = signedPolygonArea(room.points).abs();
      if (a < area) {
        area = a;
        best = room;
      }
    }
    return best == null
        ? null
        : (departmentId: best.departmentId, name: best.name);
  };
}

/// Τι λέει ο χάρτης για ένα σύμβολο: στην υπόδειξη (πέρασμα ποντικιού) τα
/// [rows] και η [warning], στα πλήρη στοιχεία (κλικ) και οι [notes].
class FloorPlanItemInfo {
  const FloorPlanItemInfo({
    required this.title,
    required this.kindLabel,
    this.rows = const [],
    this.warning,
    this.notes,
  });

  /// Όνομα, αριθμός ή κωδικός.
  final String title;

  /// «Υπάλληλος», «Τηλέφωνο», «Εξοπλισμός» ή το είδος του αντικειμένου.
  final String kindLabel;

  /// Ζεύγη «τι — τιμή»· όσα δεν έχουν τιμή παραλείπονται.
  final List<(String, String)> rows;

  /// Διαφωνία με τον Κατάλογο — π.χ. ο χώρος είναι άλλου τμήματος.
  final String? warning;

  /// Σημειώσεις αντικειμένου χάρτη — μόνο στα πλήρη στοιχεία.
  final String? notes;
}

/// Όσα χρειάζεται ο χάρτης για να περιγράψει ένα σύμβολο.
class FloorPlanInfoSources {
  const FloorPlanInfoSources({
    required this.objects,
    required this.kinds,
    required this.catalog,
    required this.placements,
    required this.departmentName,
    required this.roomAt,
    this.ports = const [],
    this.occupiedPortIds = const {},
  });

  final Map<int, FloorPlanObject> objects;
  final Map<int, FloorPlanObjectKind> kinds;
  final Map<(FloorPlanPlacementType, int), FloorPlanCatalogEntry> catalog;
  final Map<int, FloorPlanPlacement> placements;
  final String? Function(int departmentId) departmentName;

  /// Ο χώρος στο σημείο: το τμήμα του (αν είναι τμήμα) και το όνομά του.
  final ({int? departmentId, String? name})? Function(Offset world) roomAt;

  /// Οι θύρες των αντικειμένων του ορόφου, και ποιες έχουν καλώδιο — για τις
  /// προσόψεις.
  final List<FloorPlanPort> ports;
  final Set<int> occupiedPortIds;
}

/// Δίνει πληροφορίες το [view]; Οι εγγραφές του Καταλόγου πάντα· τα
/// αντικείμενα όπως ορίζει το είδος τους.
bool floorPlanItemHasInfo(
  FloorPlanObjectView view,
  Map<int, FloorPlanObjectKind> kinds,
) =>
    view.source == FloorPlanItemSource.placement ||
    (kinds[view.kindId]?.showInfo ?? true);

/// Η περιγραφή του [view]· `null` όταν η εγγραφή του δεν βρέθηκε (π.χ.
/// σβήστηκε στο μεταξύ) ή όταν το είδος του δεν δείχνει πληροφορίες.
FloorPlanItemInfo? floorPlanItemInfo(
  FloorPlanObjectView view,
  FloorPlanInfoSources sources,
) {
  final room = sources.roomAt(view.center);
  final roomDepartment = room?.departmentId;
  final roomDepartmentName = roomDepartment == null
      ? null
      : sources.departmentName(roomDepartment);
  final rows = <(String, String)>[];
  void add(String label, String? value) {
    final v = value?.trim();
    if (v != null && v.isNotEmpty) rows.add((label, v));
  }

  if (view.source == FloorPlanItemSource.object) {
    final object = sources.objects[view.id];
    if (object == null) return null;
    final kind = sources.kinds[object.kindId];
    if (kind != null && !kind.showInfo) return null;
    add('IP', object.ip);
    add('Lansweeper', object.lansweeperName);
    // Τα αντικείμενα του χάρτη δεν έχουν κάτοχο στον Κατάλογο· κάτοχος
    // είναι το τμήμα του χώρου όπου βρίσκονται.
    add('Τμήμα', roomDepartmentName);
    if (roomDepartment == null) add('Χώρος', room?.name);
    final name = object.name?.trim() ?? '';
    return FloorPlanItemInfo(
      title: name.isEmpty ? (kind?.name ?? 'Αντικείμενο') : name,
      kindLabel: kind?.name ?? 'Αντικείμενο',
      rows: rows,
      notes: object.notes,
    );
  }

  final placement = sources.placements[view.id];
  if (placement == null) return null;
  final entry = sources.catalog[(placement.type, placement.entityId)];
  if (entry == null) return null;
  final departments = [
    for (final id in entry.departmentIds) ?sources.departmentName(id),
  ]..sort();
  add('Τμήμα', departments.join(', '));
  switch (entry.type) {
    case FloorPlanPlacementType.user:
      add('Τηλέφωνα', entry.phones.join(', '));
      add('Εξοπλισμός', entry.equipment.join(', '));
    case FloorPlanPlacementType.phone:
      add('Το έχουν', entry.holders.join(', '));
    case FloorPlanPlacementType.equipment:
      add('Κάτοχος', entry.holders.join(', '));
      add('Lansweeper', entry.lansweeperName);
  }
  final mismatch =
      roomDepartment != null &&
      entry.departmentIds.isNotEmpty &&
      !entry.departmentIds.contains(roomDepartment);
  return FloorPlanItemInfo(
    title: entry.label,
    kindLabel: switch (entry.type) {
      FloorPlanPlacementType.user => 'Υπάλληλος',
      FloorPlanPlacementType.phone => 'Τηλέφωνο',
      FloorPlanPlacementType.equipment => 'Εξοπλισμός',
    },
    rows: rows,
    warning: mismatch
        ? 'Ο χώρος είναι του «${roomDepartmentName ?? 'άλλου τμήματος'}».'
        : null,
  );
}
