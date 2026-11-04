import 'dart:ui' show Offset;

import '../../../../core/models/floor_plan_element.dart';
import '../../../../core/models/floor_plan_object.dart';
import '../../../../core/models/floor_plan_object_kind.dart';
import '../../../../core/models/floor_plan_placement.dart';
import '../../../../core/models/floor_plan_port.dart';
import 'floor_plan_cabinet.dart';
import 'floor_plan_objects.dart';
import 'floor_plan_ports.dart';
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
    this.portLinks = const [],
    this.cableLines = const [],
    this.floorLabel,
    this.floorLevel,
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

  /// Οι συνδέσεις πρίζας — patch panel που αγγίζουν τον όροφο.
  final List<FloorPlanPortLink> portLinks;

  /// Το κείμενο για ό,τι είναι συνδεδεμένο σε θύρα πρίζας.
  String? connectionLabel(FloorPlanPortConnection connection) =>
      floorPlanConnectionLabel(
        connection,
        equipmentLabel: (id) =>
            catalog[(FloorPlanPlacementType.equipment, id)]?.label,
        objectLabel: (id) {
          final object = objects[id];
          if (object == null) return null;
          final name = object.name?.trim() ?? '';
          return name.isEmpty ? kinds[object.kindId]?.name : name;
        },
      );

  /// Τα καλώδια που αγγίζουν τον όροφο.
  final List<FloorPlanCableLine> cableLines;

  /// Πώς λέγεται ένας όροφος, και πού βρίσκεται σε σχέση με τους άλλους — για
  /// τις διαδρομές ανάμεσα σε ορόφους.
  final String? Function(int floorId)? floorLabel;
  final int? Function(int floorId)? floorLevel;

  String _floorName(int floorId) => floorLabel?.call(floorId) ?? 'άλλος όροφος';

  /// Τι δείχνει μια θύρα της πρόσοψης πέρα από το όνομά της· `null` όταν δεν
  /// έχει καλώδιο. Μία φορά ο πίνακας για όλη την πρόσοψη, που μπορεί να έχει
  /// εκατοντάδες θύρες.
  ///
  /// - patch panel: πίσω η πρίζα με τη συσκευή της, μπροστά το switch·
  /// - switch: η θύρα του patch panel και, σε παρένθεση, η συσκευή πίσω της:
  ///   «→ RC6.F12 (PR3918)» (σημείωση Διευθυντή, 30/10/2026).
  String? Function(FloorPlanPort port) portDetails() {
    final cables = FloorPlanPortCables(cableLines);
    final byPatchPort = {for (final l in portLinks) l.patchPortId: l};
    String? device(FloorPlanPortLink? link) => link == null
        ? null
        : floorPlanConnectionLabel(
            link.connection,
            equipmentLabel: (id) =>
                catalog[(FloorPlanPlacementType.equipment, id)]?.label,
            objectLabel: (_) => link.connectedObjectLabel,
          );
    return (port) {
      final object = objects[port.objectId];
      final isPanel =
          kinds[object?.kindId]?.symbol == FloorPlanSymbol.patchPanel;
      final other = cables.otherEnd(port.id, kFloorPlanCableFront);
      final link = byPatchPort[port.id];
      if (other == null && link == null) return null;
      final otherName = other == null ? null : floorPlanCableEndName(other);
      if (isPanel || otherName == null) {
        return [
          if (link != null)
            floorPlanPatchPortBehind(
              device(link),
              otherFloor: link.outletFloorId == link.panelFloorId
                  ? null
                  : _floorName(link.outletFloorId),
            ),
          if (otherName != null) 'Μπροστά: $otherName',
        ].join('\n');
      }
      final behind = device(other == null ? null : byPatchPort[other.portId]);
      return behind == null ? '→ $otherName' : '→ $otherName ($behind)';
    };
  }

  /// Πού οδηγούν οι θύρες της πρίζας [outletId]: η ευθεία ως κάθε καμπίνα του
  /// ορόφου, και τα αντικείμενα που φωτίζονται. Για patch panel σε άλλον όροφο
  /// η γραμμή σταματά στην πλησιέστερη σκάλα ή στον αγωγό, αν έχει σχεδιαστεί,
  /// και το σήμα λέει πού συνεχίζει.
  FloorPlanOutletRoute outletRoute(int outletId) {
    final outlet = objects[outletId];
    if (outlet == null) return const FloorPlanOutletRoute();
    final targets = <int, FloorPlanObject>{};
    final others = <int, FloorPlanOtherFloorTarget>{};
    for (final port in ports) {
      if (port.objectId != outletId) continue;
      for (final link in portLinks) {
        if (link.outletPortId != port.id) continue;
        if (link.panelFloorId != outlet.floorId) {
          final targetId = link.cabinetId ?? link.panelId;
          final name = link.cabinetId == null
              ? link.panelName
              : link.cabinetName;
          others[targetId] = FloorPlanOtherFloorTarget(
            floorId: link.panelFloorId,
            objectId: targetId,
            badge: floorPlanOtherFloorBadge(
              target: name?.trim().isNotEmpty ?? false
                  ? name!.trim()
                  : 'Καμπίνα',
              floorLabel: _floorName(link.panelFloorId),
              hereLevel: floorLevel?.call(outlet.floorId),
              thereLevel: floorLevel?.call(link.panelFloorId),
            ),
          );
          continue;
        }
        final panel = objects[link.panelId];
        final target = panel == null
            ? null
            : (objects[panel.cabinetId] ?? panel);
        if (target != null) targets[target.id] = target;
      }
    }
    return FloorPlanOutletRoute(
      from: outlet.center,
      targets: targets.values.toList(),
      otherFloors: others.values.toList(),
      riser: others.isEmpty ? null : _nearestRiser(outlet.center),
    );
  }

  FloorPlanObject? _nearestRiser(Offset from) {
    FloorPlanObject? best;
    var bestDistance = double.infinity;
    for (final o in objects.values) {
      if (kinds[o.kindId]?.symbol != FloorPlanSymbol.riser) continue;
      final distance = (o.center - from).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = o;
      }
    }
    return best;
  }
}

/// Μια καμπίνα σε άλλον όροφο, όπου καταλήγει θύρα της πρίζας.
class FloorPlanOtherFloorTarget {
  const FloorPlanOtherFloorTarget({
    required this.floorId,
    required this.objectId,
    required this.badge,
  });

  final int floorId;

  /// Η καμπίνα, ή το patch panel αν είναι έξω από καμπίνα.
  final int objectId;

  /// «↑ RC6 · 1ος».
  final String badge;
}

/// Η διαδρομή μιας πρίζας πάνω στον χάρτη.
class FloorPlanOutletRoute {
  const FloorPlanOutletRoute({
    this.from,
    this.targets = const [],
    this.otherFloors = const [],
    this.riser,
  });

  final Offset? from;

  /// Οι καμπίνες του ορόφου όπου καταλήγει (ή το patch panel, αν είναι έξω από
  /// καμπίνα).
  final List<FloorPlanObject> targets;

  /// Οι καμπίνες άλλων ορόφων όπου καταλήγει.
  final List<FloorPlanOtherFloorTarget> otherFloors;

  /// Η σκάλα ή ο αγωγός απ' όπου φεύγει για άλλον όροφο· `null` όταν δεν έχει
  /// σχεδιαστεί.
  final FloorPlanObject? riser;

  bool get isEmpty => targets.isEmpty && otherFloors.isEmpty;

  /// Πού κάθεται το σήμα του άλλου ορόφου: στη σκάλα, αλλιώς δίπλα στην πρίζα.
  Offset? get badgeAnchor => riser?.center ?? from;
}

String _objectLabel(
  FloorPlanObject object,
  Map<int, FloorPlanObjectKind> kinds,
) {
  final name = object.name?.trim() ?? '';
  return name.isEmpty ? (kinds[object.kindId]?.name ?? 'Αντικείμενο') : name;
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
    final ports = [
      for (final p in sources.ports)
        if (p.objectId == object.id) p,
    ]..sort((a, b) => a.number.compareTo(b.number));
    final cables = FloorPlanPortCables(sources.cableLines);
    if (kind?.symbol?.isOutlet ?? false) {
      for (final port in ports) {
        FloorPlanPortLink? link;
        for (final l in sources.portLinks) {
          if (l.outletPortId == port.id) link = l;
        }
        add(
          'Θύρα ${port.number}',
          floorPlanOutletPortLine(
            link: link,
            writtenName: port.writtenName,
            connected: sources.connectionLabel(port.connection),
            switchEnd: link == null
                ? null
                : cables.otherEnd(link.patchPortId, kFloorPlanCableFront),
            otherFloor: link == null || link.panelFloorId == object.floorId
                ? null
                : sources._floorName(link.panelFloorId),
          ),
        );
      }
    } else if (kind?.symbol?.isCabinet ?? false) {
      final contents = floorPlanCabinetContents(
        object.id,
        sources.objects.values,
      );
      add(
        'Περιέχει',
        [for (final o in contents) _objectLabel(o, sources.kinds)].join(', '),
      );
      final switchIds = {
        for (final o in contents)
          if (sources.kinds[o.kindId]?.symbol == FloorPlanSymbol.networkSwitch)
            o.id,
      };
      final switchPorts = [
        for (final p in sources.ports)
          if (switchIds.contains(p.objectId)) p,
      ];
      if (switchPorts.isNotEmpty) {
        add(
          'Ελεύθερες θύρες switch',
          '${switchPorts.where((p) => !sources.occupiedPortIds.contains(p.id)).length}',
        );
      }
    } else if (kind != null && floorPlanHasSinglePort(kind)) {
      for (final port in ports) {
        final other = cables.otherEnd(port.id, kFloorPlanCableFront);
        add('Καλώδιο', other == null ? null : floorPlanCableEndName(other));
      }
    }
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
