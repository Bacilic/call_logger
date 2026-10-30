import 'package:flutter/material.dart';

import '../services/floor_plan_cabinet_preferences.dart';

/// Ό,τι δίνει το παράθυρο στο πάνελ που κρατά: το ύψος των προσόψεων και
/// οι λαβές μετακίνησης.
typedef FloorPlanCabinetWindowHooks = ({
  double facadeHeight,
  ValueChanged<double> onFacadeResize,
  ValueChanged<Offset> onTitleDrag,
  VoidCallback onLayoutDone,
});

/// Το πάνελ της καμπίνας ως **μετακινήσιμο παράθυρο** πάνω στον χάρτη: σύρεται
/// από τη μπάρα τίτλου, αλλάζει μέγεθος από κάθε άκρη και γωνία. Θέση,
/// μέγεθος και ύψος προσόψεων τα θυμάται ανά χρήστη (απόφαση 30/10/2026).
///
/// Μπαίνει **κατευθείαν** σε `Stack` — το ίδιο τοποθετείται στη θέση του.
class FloorPlanCabinetWindow extends StatefulWidget {
  const FloorPlanCabinetWindow({
    super.key,
    required this.bounds,
    required this.builder,
  });

  /// Το μέγεθος της περιοχής του χάρτη· το παράθυρο δεν βγαίνει ποτέ έξω.
  final Size bounds;

  final Widget Function(BuildContext context, FloorPlanCabinetWindowHooks hooks)
  builder;

  @override
  State<FloorPlanCabinetWindow> createState() => _FloorPlanCabinetWindowState();
}

class _FloorPlanCabinetWindowState extends State<FloorPlanCabinetWindow> {
  /// Πλάτος της ζώνης που πιάνει το ποντίκι στις άκρες.
  static const double _edge = 6;

  late FloorPlanCabinetLayout _layout =
      FloorPlanCabinetPreferences.cachedLayout ??
      FloorPlanCabinetLayout.defaultFor(widget.bounds);

  @override
  void initState() {
    super.initState();
    if (FloorPlanCabinetPreferences.cachedLayout == null) _load();
  }

  Future<void> _load() async {
    final stored = await FloorPlanCabinetPreferences.readLayout();
    if (stored != null && mounted) setState(() => _layout = stored);
  }

  FloorPlanCabinetLayout get _fitted => _layout.fittedTo(widget.bounds);

  void _update(FloorPlanCabinetLayout next) =>
      setState(() => _layout = next.fittedTo(widget.bounds));

  void _save() => FloorPlanCabinetPreferences.writeLayout(_fitted);

  /// Σέρνει την άκρη [left]/[top]/[right]/[bottom] κατά [d]. Η απέναντι
  /// άκρη μένει ακίνητη.
  void _resize(
    Offset d, {
    bool left = false,
    bool top = false,
    bool right = false,
    bool bottom = false,
  }) {
    final r = _fitted.rect;
    var l = r.left, t = r.top, rr = r.right, b = r.bottom;
    if (left) {
      l = (l + d.dx).clamp(
        double.negativeInfinity,
        rr - FloorPlanCabinetLayout.minWidth,
      );
    }
    if (right) {
      rr = (rr + d.dx).clamp(
        l + FloorPlanCabinetLayout.minWidth,
        double.infinity,
      );
    }
    if (top) {
      t = (t + d.dy).clamp(
        double.negativeInfinity,
        b - FloorPlanCabinetLayout.minHeight,
      );
    }
    if (bottom) {
      b = (b + d.dy).clamp(
        t + FloorPlanCabinetLayout.minHeight,
        double.infinity,
      );
    }
    _update(_fitted.copyWith(rect: Rect.fromLTRB(l, t, rr, b)));
  }

  Widget _handle({
    required MouseCursor cursor,
    required GestureDragUpdateCallback onDrag,
  }) => MouseRegion(
    cursor: cursor,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: onDrag,
      onPanEnd: (_) => _save(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final layout = _fitted;
    final panel = widget.builder(context, (
      facadeHeight: layout.facadeHeight,
      onFacadeResize: (h) => _update(layout.copyWith(facadeHeight: h)),
      onTitleDrag: (d) =>
          _update(_fitted.copyWith(rect: _fitted.rect.shift(d))),
      onLayoutDone: _save,
    ));
    return Positioned.fromRect(
      rect: layout.rect,
      child: Stack(
        // Οι λαβές είναι μέσα στο παράθυρο: έξω από τα όριά του το ποντίκι
        // δεν θα τις έπιανε.
        children: [
          Positioned.fill(child: panel),
          // Άκρες.
          Positioned(
            left: 0,
            top: _edge,
            bottom: _edge,
            width: _edge,
            child: _handle(
              cursor: SystemMouseCursors.resizeLeft,
              onDrag: (d) => _resize(d.delta, left: true),
            ),
          ),
          Positioned(
            right: 0,
            top: _edge,
            bottom: _edge,
            width: _edge,
            child: _handle(
              cursor: SystemMouseCursors.resizeRight,
              onDrag: (d) => _resize(d.delta, right: true),
            ),
          ),
          Positioned(
            top: 0,
            left: _edge,
            right: _edge,
            height: _edge,
            child: _handle(
              cursor: SystemMouseCursors.resizeUp,
              onDrag: (d) => _resize(d.delta, top: true),
            ),
          ),
          Positioned(
            bottom: 0,
            left: _edge,
            right: _edge,
            height: _edge,
            child: _handle(
              cursor: SystemMouseCursors.resizeDown,
              onDrag: (d) => _resize(d.delta, bottom: true),
            ),
          ),
          // Γωνίες.
          Positioned(
            left: 0,
            top: 0,
            width: 2 * _edge,
            height: 2 * _edge,
            child: _handle(
              cursor: SystemMouseCursors.resizeUpLeft,
              onDrag: (d) => _resize(d.delta, left: true, top: true),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            width: 2 * _edge,
            height: 2 * _edge,
            child: _handle(
              cursor: SystemMouseCursors.resizeUpRight,
              onDrag: (d) => _resize(d.delta, right: true, top: true),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            width: 2 * _edge,
            height: 2 * _edge,
            child: _handle(
              cursor: SystemMouseCursors.resizeDownLeft,
              onDrag: (d) => _resize(d.delta, left: true, bottom: true),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            width: 2 * _edge,
            height: 2 * _edge,
            child: _handle(
              cursor: SystemMouseCursors.resizeDownRight,
              onDrag: (d) => _resize(d.delta, right: true, bottom: true),
            ),
          ),
        ],
      ),
    );
  }
}
