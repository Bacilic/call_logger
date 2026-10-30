import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/models/floor_plan_element.dart';
import '../../../../../core/models/floor_plan_state.dart';
import '../../../models/department_model.dart';
import '../floor_plan_cabinet.dart';
import '../floor_plan_geometry.dart';
import '../floor_plan_item_info.dart';
import '../floor_plan_measure.dart';
import '../floor_plan_objects.dart';
import '../floor_plan_selection.dart';
import '../floor_plan_view_transform.dart';
import 'floor_plan_item_card.dart';
import 'floor_plan_measure_painter.dart';
import 'floor_plan_painter.dart';
import '../../../../../core/models/floor_plan_object.dart';
import '../../../../../core/models/floor_plan_port.dart';
import '../floor_plan_ports.dart';
import 'floor_plan_cabinet_panel.dart';
import 'floor_plan_cabinet_window.dart';
import 'floor_plan_port_facade.dart';
import 'floor_plan_room_views.dart';

/// Ο σχεδιασμένος χάρτης ενός ενεργοποιημένου ορόφου, **μόνο για προβολή**:
/// χώροι με τα ονόματά τους, τοίχοι, κείμενα, διαστάσεις, αντικείμενα.
///
/// Ο χώρος του [highlightDepartmentId] φωτίζεται και η προβολή κεντράρει
/// εκεί· αλλιώς χωρά ολόκληρος ο όροφος. Ροδέλα = ζουμ γύρω από τον δείκτη,
/// σύρσιμο = μετακίνηση, διπλό κλικ = επιστροφή στην αρχική θέαση — όπως ο
/// μικρός χάρτης των κλήσεων με την παλιά κάτοψη.
///
/// Με [infoSources] το πέρασμα του ποντικιού πάνω από ένα σύμβολο δείχνει
/// υπόδειξη, και το κλικ ανοίγει τα πλήρη στοιχεία του.
///
/// Με [measuring] τα κλικ μετρούν απόσταση (όπως στο Google Maps): κλικ σε
/// κάθε στροφή, Enter ή διπλό κλικ για τέλος, Backspace σβήνει το τελευταίο
/// σημείο, Esc τη μέτρηση. Το σύρσιμο εξακολουθεί να μετακινεί τον χάρτη.
class FloorPlanMapView extends StatefulWidget {
  const FloorPlanMapView({
    super.key,
    required this.elements,
    required this.departments,
    required this.rotationDegrees,
    this.highlightDepartmentId,
    this.centerRequest = 0,
    this.margin = 40,
    this.measuring = false,
    this.objects = const [],
    this.infoSources,
    this.onOpenCard,
    this.focusItems = const {},
  });

  final List<FloorPlanElement> elements;

  /// Τα σύμβολα που ζητήθηκαν — ό,τι βρήκε η αναζήτηση, ή ο υπάλληλος και ο
  /// εξοπλισμός μιας κλήσης: η προβολή τα χωρά όλα, από απόσταση που
  /// φαίνονται τα σύμβολα, και τα φωτίζει. Κερδίζουν το
  /// [highlightDepartmentId].
  final Set<({FloorPlanItemSource source, int id})> focusItems;

  /// Τα αντικείμενα του ορόφου (εκτυπωτές, έπιπλα…).
  final List<FloorPlanObjectView> objects;

  /// Από πού διαβάζονται οι περιγραφές· `null` = ούτε υπόδειξη ούτε στοιχεία.
  final FloorPlanInfoSources? infoSources;

  /// Η ενέργεια «Άνοιγμα καρτέλας» για ένα σύμβολο· `null` για όσα δεν έχουν
  /// καρτέλα στον Κατάλογο (αντικείμενα του χάρτη, τηλέφωνα).
  final VoidCallback? Function(FloorPlanObjectView view)? onOpenCard;
  final Map<int, DepartmentModel> departments;
  final double rotationDegrees;
  final int? highlightDepartmentId;

  /// Κάθε αλλαγή του αριθμού ζητά νέο κεντράρισμα (π.χ. νέα αναζήτηση στο
  /// ίδιο τμήμα).
  final int centerRequest;

  /// Περιθώριο γύρω από ό,τι χωρά στην αρχική θέαση, σε pixel.
  final double margin;

  /// Τα κλικ μετρούν απόσταση αντί να μην κάνουν τίποτα.
  final bool measuring;

  @override
  State<FloorPlanMapView> createState() => _FloorPlanMapViewState();
}

class _FloorPlanMapViewState extends State<FloorPlanMapView> {
  FloorPlanViewTransform? _view;
  Size _size = Size.zero;
  Offset? _lastPan;
  Offset? _downAt;
  DateTime? _lastClickAt;

  final FocusNode _focus = FocusNode(debugLabel: 'floor-plan-map-view');
  final FloorPlanLabelCache _labelCache = FloorPlanLabelCache();
  FloorPlanMeasure _measure = FloorPlanMeasure.empty;
  Offset? _hoverWorld;
  List<FloorPlanSegment> _walls = const [];

  /// Το σύμβολο κάτω από τον δείκτη και πού είναι ο δείκτης στην οθόνη.
  FloorPlanObjectView? _hovered;
  Offset _hoverScreen = Offset.zero;

  /// Το σύμβολο του οποίου τα πλήρη στοιχεία φαίνονται.
  FloorPlanObjectView? _details;

  /// Το σύμβολο κάτω από τον δείκτη — μόνο όσα φαίνονται σε αυτό το ζουμ
  /// και δίνουν πληροφορίες· τα υπόλοιπα είναι «διάφανα» στο ποντίκι. Η
  /// καμπίνα πιάνεται πάντα, γιατί το κλικ ανοίγει το περιεχόμενό της.
  FloorPlanObjectView? _itemAt(
    Offset screen,
    FloorPlanViewTransform view, {
    bool forClick = false,
  }) {
    final sources = widget.infoSources;
    if (sources == null) return null;
    return hitTestFloorPlanObject(view.toWorld(screen), [
      for (final v in floorPlanObjectsAtZoom(widget.objects, view.pixelsPerCm))
        if (floorPlanItemHasInfo(v, sources.kinds) || (forClick && v.isCabinet))
          v,
    ]);
  }

  static String _portName(
    FloorPlanInfoSources sources,
    FloorPlanObject object,
    FloorPlanPort port,
  ) {
    final cabinetId = object.cabinetId;
    return floorPlanPortAutoName(
      symbol: sources.kinds[object.kindId]?.symbol,
      objectName: object.name,
      cabinetName: cabinetId == null ? null : sources.objects[cabinetId]?.name,
      number: port.number,
    );
  }

  /// Η πρόσοψη ενός patch panel, switch, router ή POE έξω από καμπίνα, για
  /// τα στοιχεία με κλικ· `null` για ό,τι άλλο.
  Widget? _facadeOf(FloorPlanObjectView view) {
    final sources = widget.infoSources;
    if (sources == null || view.source != FloorPlanItemSource.object) {
      return null;
    }
    final object = sources.objects[view.id];
    final symbol = object == null ? null : sources.kinds[object.kindId]?.symbol;
    if (object == null || !(symbol?.hasPortCount ?? false)) return null;
    return FloorPlanPortFacade(
      title: 'Πρόσοψη',
      symbol: symbol,
      ports: [
        for (final p in sources.ports)
          if (p.objectId == object.id) p,
      ]..sort((a, b) => a.number.compareTo(b.number)),
      occupied: sources.occupiedPortIds,
      autoName: (p) => _portName(sources, object, p),
    );
  }

  /// Το πάνελ της καμπίνας [cabinet], μόνο για ανάγνωση.
  Widget? _cabinetPanel(FloorPlanObjectView cabinet, Size size) {
    final sources = widget.infoSources;
    final object = sources?.objects[cabinet.id];
    if (sources == null || object == null) return null;
    final name = object.name?.trim() ?? '';
    final room = sources.roomAt(object.center);
    final department = room?.departmentId;
    return FloorPlanCabinetWindow(
      key: const ValueKey('cabinet-window'),
      bounds: size,
      builder: (context, hooks) => FloorPlanCabinetPanel(
        cabinetId: object.id,
        facadeHeight: hooks.facadeHeight,
        onFacadeResize: hooks.onFacadeResize,
        onTitleDrag: hooks.onTitleDrag,
        onLayoutDone: hooks.onLayoutDone,
        title: name.isEmpty ? null : name,
        where: department == null
            ? room?.name
            : sources.departmentName(department),
        units: floorPlanCabinetUnits(object),
        contents: floorPlanCabinetContents(object.id, sources.objects.values),
        kinds: sources.kinds,
        ports: sources.ports,
        occupiedPortIds: sources.occupiedPortIds,
        portAutoName: (o, p) => _portName(sources, o, p),
        onClose: () => setState(() => _details = null),
      ),
    );
  }

  FloorPlanItemInfo? _infoOf(FloorPlanObjectView view) {
    final sources = widget.infoSources;
    return sources == null ? null : floorPlanItemInfo(view, sources);
  }

  @override
  void dispose() {
    _focus.dispose();
    _labelCache.dispose();
    super.dispose();
  }

  /// Το σημείο της μέτρησης κάτω από τον δείκτη, με τον μαγνήτη στους
  /// τοίχους (Shift: χωρίς).
  Offset _snapped(Offset world, FloorPlanViewTransform view) {
    final from = _measure.isEmpty || _measure.finished
        ? null
        : _measure.points.last;
    return snapWallPoint(
      raw: world,
      walls: _walls,
      toleranceCm: view.screenToCm(10),
      from: from,
      magnetOff: HardwareKeyboard.instance.isShiftPressed,
    ).point;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.measuring || _measure.isEmpty) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final FloorPlanMeasure next;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      next = _measure.finish();
    } else if (key == LogicalKeyboardKey.backspace) {
      next = _measure.removeLast();
    } else if (key == LogicalKeyboardKey.escape) {
      next = FloorPlanMeasure.empty;
    } else {
      return KeyEventResult.ignored;
    }
    setState(() => _measure = next);
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(covariant FloorPlanMapView old) {
    super.didUpdateWidget(old);
    if (old.highlightDepartmentId != widget.highlightDepartmentId ||
        old.centerRequest != widget.centerRequest ||
        old.rotationDegrees != widget.rotationDegrees ||
        !setEquals(old.focusItems, widget.focusItems)) {
      _view = null;
    } else if (_focused(old.objects).length !=
        _focused(widget.objects).length) {
      // Τα αντικείμενα φόρτωσαν μετά τη μετάβαση: τώρα βρίσκονται τα σύμβολα.
      _view = null;
    }
    if (!widget.measuring) _measure = FloorPlanMeasure.empty;
  }

  Set<int> get _highlightedRoomIds => {
    for (final e in widget.elements)
      if (e.kind == FloorPlanElementKind.room &&
          widget.highlightDepartmentId != null &&
          e.departmentId == widget.highlightDepartmentId)
        e.id,
  };

  List<FloorPlanObjectView> _focused(List<FloorPlanObjectView> objects) {
    final focus = widget.focusItems;
    if (focus.isEmpty) return const [];
    return [
      for (final v in objects)
        if (focus.contains((source: v.source, id: v.id))) v,
    ];
  }

  FloorPlanViewTransform _fit(Size size) {
    final rotation = widget.rotationDegrees * math.pi / 180;
    final focused = _focused(widget.objects);
    if (focused.isNotEmpty) {
      // Τουλάχιστον δέκα μέτρα γύρω από τα σύμβολα: αρκετά κοντά για να
      // φαίνονται, με λίγη γειτονιά για προσανατολισμό.
      final bounds = Rect.fromPoints(
        Offset(
          focused.map((v) => v.center.dx).reduce(math.min),
          focused.map((v) => v.center.dy).reduce(math.min),
        ),
        Offset(
          focused.map((v) => v.center.dx).reduce(math.max),
          focused.map((v) => v.center.dy).reduce(math.max),
        ),
      );
      return FloorPlanViewTransform.fit(
        worldRect: Rect.fromCenter(
          center: bounds.center,
          width: math.max(1000, bounds.width + 400),
          height: math.max(1000, bounds.height + 400),
        ),
        viewport: size,
        rotationRadians: rotation,
        margin: widget.margin,
      );
    }
    final highlighted = _highlightedRoomIds;
    final focus = highlighted.isEmpty
        ? null
        : selectionBounds(highlighted, widget.elements);
    final whole = selectionBounds({
      for (final e in widget.elements) e.id,
    }, widget.elements);
    var rect =
        focus ??
        whole ??
        Rect.fromCenter(center: Offset.zero, width: 4000, height: 3000);
    if (focus != null) {
      // Γύρω από τον χώρο φαίνεται και λίγη γειτονιά, για προσανατολισμό.
      final grow = math.max(600.0, math.max(rect.width, rect.height));
      rect = rect.inflate(grow / 2);
    }
    return FloorPlanViewTransform.fit(
      worldRect: rect,
      viewport: size,
      rotationRadians: rotation,
      margin: widget.margin,
    );
  }

  Map<int, FloorPlanSegment> get _openings {
    final walls = {
      for (final e in widget.elements)
        if (e.kind == FloorPlanElementKind.wall) e.id: e,
    };
    return {
      for (final e in widget.elements)
        if (e.kind == FloorPlanElementKind.opening)
          if (elementWorldPoints(e, walls) case [final a, final b])
            e.id: FloorPlanSegment(a, b),
    };
  }

  /// Πάνω από τον χάρτη: η υπόδειξη δίπλα στον δείκτη και το πάνελ των
  /// στοιχείων στα δεξιά.
  Widget _withItemOverlays(Widget map, Size size) {
    final hovered = _hovered;
    final hoverInfo = hovered == null || hovered == _details
        ? null
        : _infoOf(hovered);
    final details = _details;
    final cabinetPanel = details != null && details.isCabinet
        ? _cabinetPanel(details, size)
        : null;
    final detailsInfo = details == null || cabinetPanel != null
        ? null
        : _infoOf(details);
    if (hoverInfo == null && detailsInfo == null && cabinetPanel == null) {
      return map;
    }
    final openCard = details == null ? null : widget.onOpenCard?.call(details);
    return Stack(
      fit: StackFit.expand,
      children: [
        map,
        if (hoverInfo != null)
          Positioned(
            left: (_hoverScreen.dx + 16).clamp(
              0,
              (size.width - 320).clamp(0, double.infinity),
            ),
            top: (_hoverScreen.dy + 16).clamp(
              0,
              (size.height - 160).clamp(0, double.infinity),
            ),
            child: FloorPlanItemTooltip(info: hoverInfo),
          ),
        ?cabinetPanel,
        if (detailsInfo != null)
          Positioned(
            top: 8,
            right: 8,
            child: FloorPlanItemDetailsPanel(
              info: detailsInfo,
              onClose: () => setState(() => _details = null),
              onOpenCard: openCard,
              footer: details == null ? null : _facadeOf(details),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _size) {
          _size = size;
          _view = null;
        }
        final view = _view ??= _fit(size);
        final elements = widget.elements;
        final walls = _walls = [
          for (final e in elements)
            if (e.kind == FloorPlanElementKind.wall && e.points.length >= 2)
              FloorPlanSegment(e.points[0], e.points[1], id: e.id),
        ];
        final openingsByWall = <int, List<({double start, double end})>>{};
        for (final e in elements) {
          final parent = e.parentId;
          if (e.kind != FloorPlanElementKind.opening || parent == null) {
            continue;
          }
          if (e.points.length < 2) continue;
          (openingsByWall[parent] ??= []).add((
            start: e.points[0].dx,
            end: e.points[1].dx,
          ));
        }
        final measuring = widget.measuring;
        final hover = _hoverWorld;
        final canvas = CustomPaint(
          size: size,
          foregroundPainter: measuring
              ? FloorPlanMeasurePainter(
                  view: view,
                  measure: _measure,
                  hover: hover == null || _measure.finished
                      ? null
                      : _snapped(hover, view),
                )
              : null,
          painter: FloorPlanPainter(
            view: view,
            walls: walls,
            openingsByWall: openingsByWall,
            rooms: buildFloorPlanRoomViews(elements, widget.departments),
            texts: [
              for (final e in elements)
                if (e.kind == FloorPlanElementKind.text && e.points.isNotEmpty)
                  e,
            ],
            dimensions: [
              for (final e in elements)
                if (e.kind == FloorPlanElementKind.dimension &&
                    e.points.length >= 3)
                  e,
            ],
            state: const FloorPlanState(floorId: 0, patternHidden: true),
            patternImage: null,
            gridVisible: false,
            selectedIds: _highlightedRoomIds,
            openingSegments: _openings,
            overlay: const FloorPlanOverlay(),
            colors: Theme.of(context).colorScheme,
            objects: widget.objects,
            selectedObjectIds: {
              for (final f in widget.focusItems)
                if (f.source == FloorPlanItemSource.object) f.id,
            },
            selectedPlacementIds: {
              for (final f in widget.focusItems)
                if (f.source == FloorPlanItemSource.placement) f.id,
            },
            labelCache: _labelCache,
          ),
        );
        final map = Listener(
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent) return;
            final factor = math.exp(-event.scrollDelta.dy / 400);
            setState(() => _view = view.zoomAt(event.localPosition, factor));
          },
          onPointerDown: (event) {
            _lastPan = event.localPosition;
            _downAt = event.localPosition;
            if (measuring) _focus.requestFocus();
          },
          onPointerMove: (event) {
            final last = _lastPan;
            if (last == null) return;
            _lastPan = event.localPosition;
            setState(() => _view = view.panBy(event.localPosition - last));
          },
          onPointerUp: (event) {
            _lastPan = null;
            final down = _downAt;
            final wasClick =
                down != null && (event.localPosition - down).distance <= 5;
            final now = DateTime.now();
            final last = _lastClickAt;
            if (wasClick &&
                last != null &&
                now.difference(last) < const Duration(milliseconds: 500)) {
              _lastClickAt = null;
              // Διπλό κλικ: στη μέτρηση κλείνει τη διαδρομή, αλλιώς πίσω
              // στην αρχική θέαση.
              setState(() {
                if (measuring) {
                  _measure = _measure.finish();
                } else {
                  _view = null;
                }
              });
              return;
            }
            if (!measuring && wasClick) {
              final item = _itemAt(event.localPosition, view, forClick: true);
              if (item != null || _details != null) {
                // Κλικ σε σύμβολο ανοίγει τα στοιχεία του· κλικ αλλού τα
                // κλείνει. Δεν μετρά ως μισό διπλό κλικ.
                setState(() => _details = item);
                _lastClickAt = null;
                return;
              }
            }
            _lastClickAt = wasClick ? now : null;
            if (measuring && wasClick) {
              final point = _snapped(view.toWorld(event.localPosition), view);
              setState(() => _measure = _measure.add(point));
            }
          },
          child: MouseRegion(
            cursor: measuring
                ? SystemMouseCursors.precise
                : SystemMouseCursors.grab,
            onHover: (event) {
              if (measuring) {
                setState(() => _hoverWorld = view.toWorld(event.localPosition));
                return;
              }
              final item = _itemAt(event.localPosition, view);
              if (item == null && _hovered == null) return;
              setState(() {
                _hovered = item;
                _hoverScreen = event.localPosition;
              });
            },
            onExit: (_) {
              if (_hoverWorld != null || _hovered != null) {
                setState(() {
                  _hoverWorld = null;
                  _hovered = null;
                });
              }
            },
            child: canvas,
          ),
        );
        if (!measuring) return _withItemOverlays(map, size);
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              map,
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: IgnorePointer(
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          floorPlanMeasureHint(_measure),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
