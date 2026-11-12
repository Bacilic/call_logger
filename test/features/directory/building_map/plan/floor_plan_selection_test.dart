// Η γεωμετρία της επιλογής: τι πιάνει το κλικ, τι χωρά στο ορθογώνιο, πώς
// μετακινούνται και γυρίζουν τα στοιχεία.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_selection_test.dart

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:call_logger/core/models/floor_plan_element.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_geometry.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const wall = FloorPlanElement(
    id: 1,
    floorId: 1,
    kind: FloorPlanElementKind.wall,
    points: [Offset(0, 0), Offset(500, 0)],
  );
  const door = FloorPlanElement(
    id: 2,
    floorId: 1,
    kind: FloorPlanElementKind.opening,
    points: [Offset(100, 0), Offset(190, 0)],
    parentId: 1,
  );
  const room = FloorPlanElement(
    id: 3,
    floorId: 1,
    kind: FloorPlanElementKind.room,
    points: [Offset(0, 0), Offset(500, 0), Offset(500, 400), Offset(0, 400)],
  );
  const label = FloorPlanElement(
    id: 4,
    floorId: 1,
    kind: FloorPlanElementKind.text,
    points: [Offset(250, 200)],
    name: 'Αποθήκη',
    fontSize: 40,
  );
  const all = [wall, door, room, label];

  bool near(Offset a, Offset b) => (a - b).distance < 1e-6;

  group('Τι πιάνει το κλικ', () {
    test('το κείμενο πάνω από τον χώρο που το περιέχει', () {
      expect(hitTestElement(const Offset(250, 200), all, 10)?.id, 4);
    });

    test('η πόρτα πριν από τον τοίχο της', () {
      expect(hitTestElement(const Offset(150, 3), all, 10)?.id, 2);
    });

    test('ο τοίχος έξω από την πόρτα', () {
      expect(hitTestElement(const Offset(400, 3), all, 10)?.id, 1);
    });

    test('ο χώρος όπου δεν υπάρχει τίποτα άλλο', () {
      expect(hitTestElement(const Offset(450, 350), all, 10)?.id, 3);
    });

    test('έξω από όλα: τίποτα', () {
      expect(hitTestElement(const Offset(900, 900), all, 10), isNull);
    });
  });

  test('το ορθογώνιο επιλέγει μόνο ό,τι χωρά ολόκληρο — όχι πόρτες μόνες', () {
    final inside = elementsInRect(Rect.fromLTWH(-10, -10, 520, 20), all);
    expect(inside, {1});
  });

  test('η μετακίνηση αφήνει την πόρτα πάνω στον τοίχο της', () {
    expect(translateElement(door, const Offset(50, 50)).points, door.points);
    expect(translateElement(wall, const Offset(50, 50)).points, const [
      Offset(50, 50),
      Offset(550, 50),
    ]);
  });

  test('η περιστροφή γυρίζει και τα γράμματα του κειμένου', () {
    final turned = rotateElement(label, const Offset(0, 0), math.pi / 2);
    expect(near(turned.points.single, const Offset(-200, 250)), isTrue);
    expect(turned.rotationDegrees, closeTo(90, 1e-9));
  });

  test('η περιστροφή χώρου γυρίζει και το μετακινημένο όνομά του', () {
    const room = FloorPlanElement(
      id: 9,
      floorId: 1,
      kind: FloorPlanElementKind.room,
      points: [Offset(0, 0), Offset(400, 0), Offset(400, 300)],
      labelOffset: Offset(100, 0),
    );
    final turned = rotateElement(room, Offset.zero, math.pi / 2);
    expect(near(turned.labelOffset!, const Offset(0, 100)), isTrue);
  });

  test('ο μαγνήτης περιστροφής κουμπώνει ανά 15°', () {
    expect(snapRadians(0.30) * 180 / math.pi, closeTo(15, 1e-9));
  });

  test('η αντιγραφή τοίχου παίρνει μαζί τις πόρτες του', () {
    expect(withOwnedOpenings({1}, all).map((e) => e.id), [1, 2]);
  });

  group('Μετακίνηση τοίχων με μαγνήτη και οδηγούς', () {
    const ends = [Offset(0, 0), Offset(100, 0)];
    bool visible(Offset _) => true;

    test('άκρη κοντά σε άκρη άλλου τοίχου: όλη η επιλογή κουμπώνει εκεί', () {
      final result = snapWallMove(
        movingEnds: ends,
        delta: Offset.zero,
        others: const [FloorPlanSegment(Offset(103, 4), Offset(200, 4))],
        toleranceCm: 10,
        guideEndVisible: visible,
      );
      expect(result.delta, const Offset(3, 4));
      expect(result.snap!.kind, FloorPlanSnapKind.endpoint);
    });

    test('χωρίς τοίχο κοντά, κουμπώνει στον οδηγό άλλου τοίχου', () {
      // Ο κάθετος τοίχος δίνει από την άκρη του (0,50) οριζόντιο οδηγό y=50.
      final result = snapWallMove(
        movingEnds: const [Offset(200, 0), Offset(300, 0)],
        delta: const Offset(0, 47),
        others: const [FloorPlanSegment(Offset(0, 50), Offset(0, 100))],
        toleranceCm: 10,
        guideEndVisible: visible,
      );
      expect(result.delta.dy, closeTo(50, 1e-9));
      expect(result.snap!.kind, FloorPlanSnapKind.guide);
      expect(result.snap!.guides, isNotEmpty);
    });

    test('άκρη πάνω σε άκρη κερδίζει άκρη που απλώς γλιστρά σε σώμα', () {
      // Η αριστερή άκρη κάθεται ήδη πάνω στον μακρύ κάθετο τοίχο (διόρθωση
      // μηδέν)· η δεξιά βρίσκει άκρη 3 εκ. πιο πέρα — αυτή αποφασίζει.
      final result = snapWallMove(
        movingEnds: const [Offset(0, 0), Offset(400, 0)],
        delta: const Offset(0, 297),
        others: const [
          FloorPlanSegment(Offset(0, -100), Offset(0, 1000)),
          FloorPlanSegment(Offset(403, 300), Offset(500, 300)),
        ],
        toleranceCm: 10,
        guideEndVisible: visible,
      );
      expect(result.delta, const Offset(3, 300));
    });

    test('μακριά από όλα, η μετακίνηση μένει ελεύθερη', () {
      final result = snapWallMove(
        movingEnds: ends,
        delta: const Offset(37, 41),
        others: const [FloorPlanSegment(Offset(500, 500), Offset(600, 500))],
        toleranceCm: 10,
        guideEndVisible: visible,
      );
      expect(result.delta, const Offset(37, 41));
      expect(result.snap, isNull);
    });
  });

  group('Αλλαγή μήκους τοίχου από την άκρη του', () {
    WallEndResize resize(
      int end,
      Offset to, {
      List<FloorPlanSegment> others = const [],
      bool magnetOff = false,
    }) => resizeWallEnd(
      wall: wall,
      end: end,
      to: to,
      openings: all,
      others: others,
      toleranceCm: 20,
      magnetOff: magnetOff,
    )!;

    test('η άκρη κινείται μόνο πάνω στην ευθεία: η κλίση δεν αλλάζει και η '
        'άλλη άκρη μένει ακίνητη', () {
      final longer = resize(1, const Offset(700, 240));
      expect(longer.wall.points, const [Offset(0, 0), Offset(700, 0)]);
    });

    test('χωρίς άλλον τοίχο κοντά, το μήκος στρογγυλεύει ανά 5 εκατοστά· με '
        'Shift μένει όπου δείχνει ο δείκτης', () {
      expect(resize(1, const Offset(613, 0)).wall.points[1].dx, 615);
      expect(
        resize(1, const Offset(613, 0), magnetOff: true).wall.points[1].dx,
        613,
      );
    });

    test('η άκρη κουμπώνει εκεί όπου η ευθεία συναντά άλλον τοίχο', () {
      const other = FloorPlanSegment(
        Offset(632, -200),
        Offset(632, 200),
        id: 9,
      );
      final snapped = resize(1, const Offset(620, 30), others: [other]);
      expect(snapped.wall.points[1], const Offset(632, 0));
      expect(snapped.snapKind, FloorPlanSnapKind.wallBody);
    });

    test('το κόντεμα σταματά στην άκρη της πόρτας', () {
      // Η πόρτα πιάνει από 100 ως 190 εκ. από την αρχή.
      expect(resize(1, const Offset(50, 0)).wall.points[1].dx, 190);
      expect(resize(0, const Offset(400, 0)).wall.points[0].dx, 100);
    });

    test('όταν σύρεται η αρχή, η πόρτα μένει στο ίδιο σημείο του σχεδίου', () {
      final shorter = resize(0, const Offset(60, 0));
      expect(shorter.wall.points, const [Offset(60, 0), Offset(500, 0)]);
      final walls = {shorter.wall.id: shorter.wall};
      expect(elementWorldPoints(shorter.openings.single, walls), const [
        Offset(100, 0),
        Offset(190, 0),
      ]);
    });

    test('η άκρη σταματά πάνω σε γραμμή-οδηγό: στο ύψος της άκρης ενός '
        'άλλου τοίχου που δεν τον συναντά', () {
      // Κατακόρυφος τοίχος πιο ψηλά, που τελειώνει κάτω στο x = 640.
      const far = FloorPlanSegment(Offset(640, -400), Offset(640, -150), id: 9);
      final snapped = resize(1, const Offset(637, 20), others: [far]);
      expect(snapped.wall.points[1], const Offset(640, 0));
      expect(snapped.snapKind, FloorPlanSnapKind.guide);
      expect(snapped.guides.single.origin, const Offset(640, -150));
    });

    group('Ελεύθερη μετακίνηση της άκρης (Ctrl)', () {
      WallEndResize free(
        int end,
        Offset to, {
        List<FloorPlanSegment> others = const [],
        bool magnetOff = false,
      }) => resizeWallEnd(
        wall: wall,
        end: end,
        to: to,
        openings: all,
        others: others,
        toleranceCm: 20,
        magnetOff: magnetOff,
        free: true,
      )!;

      test('ο τοίχος αλλάζει κλίση, με τη γωνία κουμπωμένη ανά 15° από τη '
          'σταθερή άκρη', () {
        final turned = free(1, const Offset(402, 398));
        expect(turned.wall.points[0], Offset.zero);
        final end = turned.wall.points[1];
        expect(end.dx, closeTo(end.dy, 0.01));
      });

      test('η άκρη κολλά στην άκρη άλλου τοίχου, όποια κλίση κι αν δίνει', () {
        const other = FloorPlanSegment(Offset(430, 170), Offset(900, 170));
        final joined = free(1, const Offset(436, 163), others: [other]);
        expect(joined.wall.points[1], const Offset(430, 170));
        expect(joined.snapKind, FloorPlanSnapKind.endpoint);
      });

      test('με Shift η άκρη πηγαίνει ακριβώς όπου δείχνει ο δείκτης', () {
        final loose = free(1, const Offset(402, 398), magnetOff: true);
        expect(loose.wall.points[1], const Offset(402, 398));
      });

      test('ο τοίχος δεν γίνεται κοντύτερος από την πόρτα του', () {
        // Η πόρτα φτάνει ως τα 190 εκ. από την αρχή.
        final short = free(1, const Offset(0, 50), magnetOff: true);
        expect(
          (short.wall.points[1] - Offset.zero).distance,
          closeTo(190, 0.01),
        );
      });

      test('όταν σύρεται η αρχή, η πόρτα κρατά την απόστασή της από το '
          'τέλος', () {
        // Η αρχή πάει κάθετα πάνω από το τέλος: νέο μήκος 450, από 500. Η
        // πόρτα απείχε 400 από το τέλος, άρα τώρα 50 από τη νέα αρχή.
        final turned = free(0, const Offset(500, -450), magnetOff: true);
        expect(turned.openings.single.points.first.dx, closeTo(50, 0.01));
        expect(
          turned.openings.single.points.last.dx -
              turned.openings.single.points.first.dx,
          closeTo(90, 0.01),
        );
      });
    });

    test('όταν σύρεται το τέλος, η πόρτα δεν αλλάζει', () {
      final longer = resize(1, const Offset(800, 0));
      expect(longer.openings.single.points, door.points);
    });
  });

  test('η γραμμή διάστασης απέχει όσο ορίζει το τρίτο σημείο', () {
    const dim = FloorPlanElement(
      id: 5,
      floorId: 1,
      kind: FloorPlanElementKind.dimension,
      points: [Offset(0, 0), Offset(400, 0), Offset(123, 60)],
    );
    final line = dimensionLine(dim)!;
    expect(near(line.a, const Offset(0, 60)), isTrue);
    expect(near(line.b, const Offset(400, 60)), isTrue);
  });
}
