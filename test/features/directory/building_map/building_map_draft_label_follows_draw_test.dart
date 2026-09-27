import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:call_logger/features/directory/building_map/building_map_label_layout.dart';
import 'package:call_logger/features/directory/building_map/providers/building_map_providers.dart';
import 'package:call_logger/features/directory/models/department_model.dart';

/// Συμβόλαιο: όσο υπάρχει ενεργό προσχέδιο για το επιλεγμένο τμήμα, η ετικέτα
/// ακολουθεί τη γεωμετρία του προσχεδίου — και στη Σχεδίαση, όχι μόνο στην
/// Επεξεργασία, και ανεξάρτητα από το αν το τμήμα έχει αποθηκευμένη θέση.
void main() {
  const canvas = Size(1000, 800);
  const sheet = '7';

  const draft = DraftDepartmentShape(x: 0.2, y: 0.3, width: 0.1, height: 0.1);

  test(
    'Σχεδίαση νέου τμήματος χωρίς αποθηκευμένη θέση: η ετικέτα φαίνεται',
    () {
      final dep = DepartmentModel(id: 5, name: 'Debug Κενό name_key');

      final layout = computeMapLabelLayout(
        dep: dep,
        sheetIdString: sheet,
        draftShape: draft,
        toolMode: MapToolMode.draw,
        highlightDepartmentId: 5,
        canvasSize: canvas,
        sheetRotationRadians: 0,
      );

      expect(layout, isNotNull);
      // Κέντρο προσχεδίου: (0.25, 0.35) → (250, 280) στον καμβά.
      expect(layout!.labelCenter.dx, closeTo(250, 0.01));
      expect(layout.labelCenter.dy, closeTo(280, 0.01));
    },
  );

  test(
    'Σχεδίαση πάνω σε τμήμα με παλιά θέση: η ετικέτα ακολουθεί το προσχέδιο',
    () {
      final dep = DepartmentModel(
        id: 5,
        name: 'Γραμματεία ΤΕΠ',
        mapFloor: sheet,
        mapX: 0.8,
        mapY: 0.8,
        mapWidth: 0.05,
        mapHeight: 0.05,
      );

      final layout = computeMapLabelLayout(
        dep: dep,
        sheetIdString: sheet,
        draftShape: draft,
        toolMode: MapToolMode.draw,
        highlightDepartmentId: 5,
        canvasSize: canvas,
        sheetRotationRadians: 0,
      );

      expect(layout, isNotNull);
      expect(layout!.labelCenter.dx, closeTo(250, 0.01));
      expect(layout.labelCenter.dy, closeTo(280, 0.01));
    },
  );

  test('Άλλο τμήμα του φύλλου δεν κλέβει το προσχέδιο', () {
    final other = DepartmentModel(
      id: 9,
      name: 'Ακτινολογικό',
      mapFloor: sheet,
      mapX: 0.8,
      mapY: 0.8,
      mapWidth: 0.05,
      mapHeight: 0.05,
    );

    final layout = computeMapLabelLayout(
      dep: other,
      sheetIdString: sheet,
      draftShape: draft,
      toolMode: MapToolMode.draw,
      highlightDepartmentId: 5,
      canvasSize: canvas,
      sheetRotationRadians: 0,
    );

    expect(layout, isNotNull);
    // Κέντρο αποθηκευμένου: (0.825, 0.825) → (825, 660).
    expect(layout!.labelCenter.dx, closeTo(825, 0.01));
    expect(layout.labelCenter.dy, closeTo(660, 0.01));
  });

  test('Χωρίς προσχέδιο και χωρίς αποθηκευμένη θέση: καμία ετικέτα', () {
    final dep = DepartmentModel(id: 5, name: 'Debug Κενό name_key');

    final layout = computeMapLabelLayout(
      dep: dep,
      sheetIdString: sheet,
      draftShape: null,
      toolMode: MapToolMode.draw,
      highlightDepartmentId: 5,
      canvasSize: canvas,
      sheetRotationRadians: 0,
    );

    expect(layout, isNull);
  });
}
