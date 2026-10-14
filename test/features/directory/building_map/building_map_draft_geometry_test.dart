// Γεωμετρία προσχεδίου στον καμβά του χάρτη: ποια λαβή πιάνει ο δείκτης και
// πώς αλλάζει το σχήμα όταν σύρεται. Τιμές από εκτέλεση του σημερινού κώδικα.
//
//   flutter test test/features/directory/building_map/building_map_draft_geometry_test.dart

import 'dart:math' as math;

import 'package:call_logger/features/directory/building_map/building_map_draft_geometry.dart';
import 'package:call_logger/features/directory/building_map/building_map_label_layout.dart';
import 'package:call_logger/features/directory/building_map/providers/building_map_providers.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(1000, 800);
  // Σε px: ορθογώνιο 200,200 – 400,400· κέντρο ετικέτας (300, 460)· άγκυρα (300, 400).
  const draft = DraftDepartmentShape(
    x: 0.2,
    y: 0.25,
    width: 0.2,
    height: 0.25,
    labelOffsetX: 0.0,
    labelOffsetY: 0.2,
  );

  group('Ποια λαβή πιάνει ο δείκτης', () {
    test('κάθε λαβή του προσχεδίου αναγνωρίζεται στη θέση της', () {
      EditHandleType hit(Offset p) => hitTestDraftHandle(draft, p, size, 0);

      expect(hit(const Offset(300, 300)), EditHandleType.move);
      expect(hit(const Offset(300, 460)), EditHandleType.label);
      expect(hit(const Offset(375, 485)), EditHandleType.labelBoxBottomRight);
      expect(hit(const Offset(300, 400)), EditHandleType.anchor);
      expect(hit(const Offset(200, 200)), EditHandleType.topLeft);
      expect(hit(const Offset(400, 400)), EditHandleType.bottomRight);
      expect(hit(const Offset(300, 176)), EditHandleType.rotate);
      expect(hit(const Offset(900, 700)), EditHandleType.none);
      // 13 px έξω από τη γωνία: εκτός εμβέλειας λαβής.
      expect(hit(const Offset(187, 200)), EditHandleType.none);
    });

    test('με περιστραμμένο φύλλο οι λαβές ακολουθούν την περιστροφή', () {
      EditHandleType hit(Offset p) =>
          hitTestDraftHandle(draft, p, size, math.pi);

      expect(hit(const Offset(800, 600)), EditHandleType.topLeft);
      expect(hit(const Offset(700, 500)), EditHandleType.move);
      expect(hit(const Offset(200, 200)), EditHandleType.none);
    });
  });

  group('Σύρσιμο λαβής', () {
    test('η μετακίνηση κρατά την ετικέτα στην ίδια θέση του καμβά', () {
      final moved = dragDraftWithHandle(
        startDraft: draft,
        handle: EditHandleType.move,
        pointerStartNormalized: const Offset(0.3, 0.3),
        currentNormalized: const Offset(0.4, 0.35),
      )!;

      expect(moved.x, closeTo(0.3, 1e-9));
      expect(moved.y, closeTo(0.3, 1e-9));
      expect(draftLabelCenter(moved, size), const Offset(300, 460));
    });

    test('η μετακίνηση σταματά στην άκρη του φύλλου', () {
      final moved = dragDraftWithHandle(
        startDraft: draft,
        handle: EditHandleType.move,
        pointerStartNormalized: const Offset(0.3, 0.3),
        currentNormalized: const Offset(1.0, 1.0),
      )!;

      expect(moved.x, 0.8);
      expect(moved.y, 0.75);
    });

    test('η λαβή περιστροφής στρέφει κατά τη γωνία του συρσίματος', () {
      final rotated = dragDraftWithHandle(
        startDraft: draft,
        handle: EditHandleType.rotate,
        pointerStartNormalized: const Offset(0.3, 0.1),
        currentNormalized: const Offset(0.5, 0.375),
      )!;

      expect(rotated.rotation, closeTo(math.pi / 2, 1e-9));
    });

    test('οι γωνίες πλαισίου ετικέτας δεν αλλάζουν το σχήμα εδώ', () {
      for (final handle in [
        EditHandleType.labelBoxTopLeft,
        EditHandleType.labelBoxBottomRight,
        EditHandleType.none,
      ]) {
        expect(
          dragDraftWithHandle(
            startDraft: draft,
            handle: handle,
            pointerStartNormalized: Offset.zero,
            currentNormalized: Offset.zero,
          ),
          isNull,
        );
      }
    });

    test('η γωνία μεγαλώνει το σχήμα με σταθερή την απέναντι γωνία', () {
      final resized = resizeDraftFromHandle(
        startDraft: draft,
        handle: EditHandleType.bottomRight,
        currentNormalized: const Offset(0.5, 0.6),
      );

      expect(resized.x, 0.2);
      expect(resized.y, 0.25);
      expect(resized.width, closeTo(0.3, 1e-9));
      expect(resized.height, closeTo(0.35, 1e-9));
    });

    test('η γωνία δεν περνά την απέναντι — μένει το ελάχιστο μέγεθος', () {
      final resized = resizeDraftFromHandle(
        startDraft: draft,
        handle: EditHandleType.topLeft,
        currentNormalized: const Offset(0.9, 0.9),
      );

      expect(resized.x, closeTo(0.395, 1e-9));
      expect(resized.y, closeTo(0.495, 1e-9));
      expect(resized.width, closeTo(kBuildingMapMinDraftSize, 1e-9));
      expect(resized.height, closeTo(kBuildingMapMinDraftSize, 1e-9));
    });

    test('το πλαίσιο ετικέτας μεγαλώνει συμμετρικά γύρω από το κέντρο', () {
      final resized = resizeLabelBoxFromHandle(
        startDraft: draft,
        handle: EditHandleType.labelBoxBottomRight,
        localPositionCanvas: const Offset(420, 500),
        canvasSize: size,
        sheetRotationRad: 0,
        labelText: 'Α',
      );

      expect(resized.labelWidth, closeTo(240, 1e-9));
      expect(resized.labelHeight, 80);
    });

    test('το πλαίσιο ετικέτας δεν στενεύει κάτω από τη μεγαλύτερη λέξη', () {
      final resized = resizeLabelBoxFromHandle(
        startDraft: draft,
        handle: EditHandleType.labelBoxBottomRight,
        localPositionCanvas: const Offset(301, 461),
        canvasSize: size,
        sheetRotationRad: 0,
        labelText: 'Ακτινολογικό',
      );

      expect(
        resized.labelWidth,
        computeMinMapLabelBoxWidthForText('Ακτινολογικό'),
      );
      expect(resized.labelHeight, kBuildingMapLabelMinHeight);
    });
  });

  group('Θέση μολυβιού επωνυμίας', () {
    const pencil = Rect.fromLTWH(0, 0, 40, 40);

    test('κάθεται δεξιά από το κείμενο όταν χωρά', () {
      expect(
        resolvePencilHitRect(
          raw: pencil,
          textRect: const Rect.fromLTWH(100, 100, 200, 30),
          canvasSize: size,
        ),
        const Rect.fromLTRB(303, 95, 343, 135),
      );
    });

    test('στη δεξιά άκρη ανεβαίνει πάνω από το κείμενο', () {
      expect(
        resolvePencilHitRect(
          raw: pencil,
          textRect: const Rect.fromLTWH(800, 100, 190, 30),
          canvasSize: size,
        ),
        const Rect.fromLTRB(950, 57, 990, 97),
      );
    });

    test('στην πάνω δεξιά γωνία κατεβαίνει κάτω από το κείμενο', () {
      expect(
        resolvePencilHitRect(
          raw: pencil,
          textRect: const Rect.fromLTWH(800, 10, 190, 30),
          canvasSize: size,
        ),
        const Rect.fromLTRB(950, 43, 990, 83),
      );
    });
  });

  test(
    'σημείο καμβά σε θέση φύλλου: ακολουθεί την περιστροφή, κόβεται στα όρια',
    () {
      expect(
        localToNormalized(const Offset(250, 200), size, 0),
        const Offset(0.25, 0.25),
      );
      expect(
        localToNormalized(const Offset(250, 200), size, math.pi),
        const Offset(0.75, 0.75),
      );
      expect(
        localToNormalized(const Offset(-50, 900), size, 0),
        const Offset(0, 1),
      );
    },
  );

  group('Διαφέρει το προσχέδιο από την αποθηκευμένη θέση;', () {
    DepartmentModel saved({String floor = '3', double? labelOffsetY = 0.2}) =>
        DepartmentModel(
          id: 1,
          name: 'Τ',
          mapFloor: floor,
          mapX: 0.2,
          mapY: 0.25,
          mapWidth: 0.2,
          mapHeight: 0.25,
          mapLabelOffsetY: labelOffsetY,
        );

    test('ίδιο σχήμα: καμία αλλαγή (κενή μετατόπιση ετικέτας = μηδέν)', () {
      expect(
        draftShapeDiffersFromSaved(dept: saved(), draft: draft, sheetStr: '3'),
        isFalse,
      );
    });

    test('αποθηκευμένο σε άλλο φύλλο: αλλαγή', () {
      expect(
        draftShapeDiffersFromSaved(
          dept: saved(floor: '9'),
          draft: draft,
          sheetStr: '3',
        ),
        isTrue,
      );
    });

    test('μετακινημένη ετικέτα: αλλαγή', () {
      expect(
        draftShapeDiffersFromSaved(
          dept: saved(labelOffsetY: 0.1),
          draft: draft,
          sheetStr: '3',
        ),
        isTrue,
      );
    });
  });
}
