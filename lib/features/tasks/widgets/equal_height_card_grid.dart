import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Πλέγμα καρτών όπου **όλες** οι κάρτες έχουν το ύψος της ψηλότερης — και
/// ανάμεσα σε διαφορετικές σειρές, όχι μόνο μέσα στην ίδια.
///
/// Η τελευταία, ελλιπής σειρά μοιράζεται όλο το πλάτος, ώστε καμία κάρτα να
/// μη μένει μόνη της με κενό δίπλα της (π.χ. 5 κάρτες σε 3 στήλες → 3 + 2).
class EqualHeightCardGrid extends MultiChildRenderObjectWidget {
  const EqualHeightCardGrid({
    super.key,
    required this.columns,
    this.spacing = 10,
    required super.children,
  });

  final int columns;
  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderEqualHeightCardGrid(columns: columns, spacing: spacing);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEqualHeightCardGrid renderObject,
  ) {
    renderObject
      ..columns = columns
      ..spacing = spacing;
  }
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {}

class RenderEqualHeightCardGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  RenderEqualHeightCardGrid({required int columns, required this._spacing})
    : _columns = math.max(1, columns);

  int _columns;
  set columns(int value) {
    final v = math.max(1, value);
    if (v == _columns) return;
    _columns = v;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) {
      child.parentData = _GridParentData();
    }
  }

  List<RenderBox> get _children {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  /// Πόσες κάρτες έχει η σειρά όπου ανήκει η κάρτα [index].
  int _perRow(int index, int count) {
    final lastRowStart = (count - 1) ~/ _columns * _columns;
    return index >= lastRowStart ? count - lastRowStart : _columns;
  }

  double _cardWidth(double maxWidth, int perRow) =>
      math.max(0, (maxWidth - _spacing * (perRow - 1)) / perRow);

  double _cardHeight(List<RenderBox> children, double maxWidth) {
    var tallest = 0.0;
    for (var i = 0; i < children.length; i++) {
      final w = _cardWidth(maxWidth, _perRow(i, children.length));
      tallest = math.max(tallest, children[i].getMaxIntrinsicHeight(w));
    }
    return tallest;
  }

  double _totalHeight(int count, double cardHeight) {
    if (count == 0) return 0;
    final rows = (count + _columns - 1) ~/ _columns;
    return rows * cardHeight + (rows - 1) * _spacing;
  }

  @override
  void performLayout() {
    final children = _children;
    final maxWidth = constraints.maxWidth;
    final cardHeight = _cardHeight(children, maxWidth);
    var x = 0.0;
    var y = 0.0;
    for (var i = 0; i < children.length; i++) {
      final perRow = _perRow(i, children.length);
      final w = _cardWidth(maxWidth, perRow);
      final child = children[i];
      child.layout(
        BoxConstraints.tightFor(width: w, height: cardHeight),
        parentUsesSize: false,
      );
      (child.parentData! as _GridParentData).offset = Offset(x, y);
      final endOfRow = i == children.length - 1 || (i + 1) % _columns == 0;
      if (endOfRow) {
        x = 0;
        y += cardHeight + _spacing;
      } else {
        x += w + _spacing;
      }
    }
    size = constraints.constrain(
      Size(maxWidth, _totalHeight(children.length, cardHeight)),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final children = _children;
    return _totalHeight(children.length, _cardHeight(children, width));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
