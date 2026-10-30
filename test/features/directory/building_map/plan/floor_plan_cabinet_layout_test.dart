// Θέση και μέγεθος του πάνελ της καμπίνας: δεν βγαίνει ποτέ έξω από τον
// χάρτη, και επιβιώνει της αποθήκευσης.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_cabinet_layout_test.dart

import 'dart:convert';
import 'dart:ui' show Rect, Size;

import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_cabinet_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bounds = Size(1200, 800);

  test('από προεπιλογή στα δεξιά, σε όλο το ύψος', () {
    final layout = FloorPlanCabinetLayout.defaultFor(bounds);
    expect(layout.rect.right, 1192);
    expect(layout.rect.top, 8);
    expect(layout.rect.height, 784);
  });

  test('όταν μικρύνει το παράθυρο, το πάνελ μένει μέσα στον χάρτη', () {
    const moved = FloorPlanCabinetLayout(
      rect: Rect.fromLTWH(900, 300, 520, 700),
      facadeHeight: 220,
    );
    final fitted = moved.fittedTo(const Size(1000, 600));
    expect(fitted.rect.right, lessThanOrEqualTo(992));
    expect(fitted.rect.bottom, lessThanOrEqualTo(592));
    expect(fitted.rect.left, greaterThanOrEqualTo(8));
  });

  test('ποτέ μικρότερο από το ελάχιστο', () {
    const tiny = FloorPlanCabinetLayout(
      rect: Rect.fromLTWH(100, 100, 50, 50),
      facadeHeight: 10,
    );
    final fitted = tiny.fittedTo(bounds);
    expect(fitted.rect.width, FloorPlanCabinetLayout.minWidth);
    expect(fitted.rect.height, FloorPlanCabinetLayout.minHeight);
    expect(fitted.facadeHeight, FloorPlanCabinetLayout.minFacadeHeight);
  });

  test('η αποθήκευση το φέρνει πίσω ίδιο', () {
    const layout = FloorPlanCabinetLayout(
      rect: Rect.fromLTWH(40, 50, 600, 500),
      facadeHeight: 260,
    );
    final back = FloorPlanCabinetLayout.fromJson(
      jsonDecode(jsonEncode(layout.toJson())),
    );
    expect(back!.rect, layout.rect);
    expect(back.facadeHeight, 260);
  });
}
