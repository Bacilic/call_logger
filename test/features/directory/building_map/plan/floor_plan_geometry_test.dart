// Η γεωμετρία της σχεδίασης τοίχων: μαγνήτης, ανοίγματα, ενώσεις γωνιών,
// βαθμονόμηση, πληκτρολόγηση μήκους.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_geometry_test.dart

import 'dart:math' as math;

import 'package:call_logger/features/directory/building_map/plan/floor_plan_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool near(Offset a, Offset b) => (a - b).distance < 0.01;

  group('Μαγνήτης', () {
    test('σχεδόν οριζόντια γραμμή κουμπώνει στις 0° με στρογγυλό μήκος', () {
      final p = snapAngleAndLength(Offset.zero, const Offset(418, 9));
      expect(near(p, const Offset(420, 0)), isTrue, reason: '$p');
    });

    test('κουμπώνει ανά 15°', () {
      // ~44° → 45°
      final p = snapAngleAndLength(Offset.zero, const Offset(100, 97));
      expect((p.dx - p.dy).abs() < 0.01, isTrue, reason: '$p');
    });

    test('η άκρη υπάρχοντος τοίχου υπερισχύει της γωνίας', () {
      const walls = [FloorPlanSegment(Offset(0, 0), Offset(300, 0))];
      final snap = snapWallPoint(
        raw: const Offset(303, 4),
        walls: walls,
        toleranceCm: 10,
        from: const Offset(300, 300),
      );
      expect(snap.kind, FloorPlanSnapKind.endpoint);
      expect(snap.point, const Offset(300, 0));
    });

    test('κοντά στο σώμα τοίχου κολλά πάνω του', () {
      const walls = [FloorPlanSegment(Offset(0, 0), Offset(300, 0))];
      final snap = snapWallPoint(
        raw: const Offset(80, 6),
        walls: walls,
        toleranceCm: 10,
      );
      expect(snap.kind, FloorPlanSnapKind.wallBody);
      expect(snap.point, const Offset(80, 0));
    });

    test('κοντά στη μέση τοίχου κολλά ακριβώς στη μέση', () {
      const walls = [FloorPlanSegment(Offset(0, 0), Offset(300, 0))];
      final snap = snapWallPoint(
        raw: const Offset(144, 6),
        walls: walls,
        toleranceCm: 10,
      );
      expect(snap.kind, FloorPlanSnapKind.midpoint);
      expect(snap.point, const Offset(150, 0));
    });

    test('ο ίσιος τοίχος δεν λοξεύει για να βρει τη μέση του απέναντι', () {
      const walls = [FloorPlanSegment(Offset(0, 0), Offset(300, 0))];
      // Η κατακόρυφος από το σημείο αφετηρίας πέφτει 6 εκ. πριν από τη μέση.
      final snap = snapWallPoint(
        raw: const Offset(146, 3),
        walls: walls,
        toleranceCm: 10,
        from: const Offset(144, 500),
      );
      expect(snap.kind, FloorPlanSnapKind.wallBody);
      expect(near(snap.point, const Offset(144, 0)), isTrue);
    });

    test('τοίχος που καταλήγει πάνω σε άλλον κρατά τη γωνία του: η άκρη '
        'πέφτει εκεί που η ίσια γραμμή συναντά τον τοίχο, όχι κάτω από τον '
        'δείκτη', () {
      const walls = [FloorPlanSegment(Offset(-300, 0), Offset(500, 0))];
      // Από κάτω προς τα πάνω, με τον δείκτη 12 εκ. δεξιά από την κατακόρυφο.
      final snap = snapWallPoint(
        raw: const Offset(12, 4),
        walls: walls,
        toleranceCm: 10,
        from: const Offset(0, 500),
      );
      expect(snap.kind, FloorPlanSnapKind.wallBody);
      expect(near(snap.point, Offset.zero), isTrue, reason: '${snap.point}');
    });

    test('όταν η ίσια γραμμή δεν συναντά τον τοίχο, η άκρη κολλά όπως πριν '
        'στο πλησιέστερο σημείο του', () {
      // Ο τοίχος τελειώνει πριν από την κατακόρυφο του σημείου αφετηρίας.
      const walls = [FloorPlanSegment(Offset(8, 0), Offset(300, 0))];
      final snap = snapWallPoint(
        raw: const Offset(22, 4),
        walls: walls,
        toleranceCm: 10,
        from: const Offset(0, 500),
      );
      expect(snap.kind, FloorPlanSnapKind.wallBody);
      expect(snap.point, const Offset(22, 0));
    });

    group('Γραμμές-οδηγοί από τις άκρες τοίχων', () {
      // Οριζόντιος τοίχος που τελειώνει στο 300, και ένας κατακόρυφος πιο
      // δεξιά που τελειώνει κάτω στο ύψος 200.
      const horizontal = FloorPlanSegment(Offset(0, 0), Offset(300, 0), id: 1);
      const vertical = FloorPlanSegment(
        Offset(600, 50),
        Offset(600, 200),
        id: 2,
      );

      test('πρώτο σημείο κοντά στην προέκταση τοίχου πέφτει πάνω της', () {
        final snap = snapWallPoint(
          raw: const Offset(450, 4),
          walls: const [horizontal],
          toleranceCm: 10,
        );
        expect(snap.kind, FloorPlanSnapKind.guide);
        expect(near(snap.point, const Offset(450, 0)), isTrue);
        expect(snap.guides.single.origin, const Offset(300, 0));
      });

      test('κοντά σε δύο οδηγούς πέφτει στη διασταύρωσή τους — η νοητή '
          'γωνία', () {
        // Η προέκταση του οριζόντιου (y = 0) και η προέκταση του
        // κατακόρυφου προς τα πάνω (x = 600).
        final snap = snapWallPoint(
          raw: const Offset(596, 4),
          walls: const [horizontal, vertical],
          toleranceCm: 10,
        );
        expect(snap.kind, FloorPlanSnapKind.guide);
        expect(near(snap.point, const Offset(600, 0)), isTrue);
        expect(snap.guides, hasLength(2));
      });

      test('δεύτερο σημείο: ο τοίχος κρατά τη γωνία του και σταματά πάνω '
          'στον οδηγό, στο ύψος της άκρης του άλλου τοίχου', () {
        // Από πάνω προς τα κάτω, με τον δείκτη λίγο λοξά και 4 εκ. πριν από
        // το ύψος 200 όπου τελειώνει ο κατακόρυφος.
        final snap = snapWallPoint(
          raw: const Offset(408, 196),
          walls: const [vertical],
          toleranceCm: 10,
          from: const Offset(400, -100),
        );
        expect(snap.kind, FloorPlanSnapKind.guide);
        expect(near(snap.point, const Offset(400, 200)), isTrue);
      });

      test('μακριά από κάθε οδηγό ισχύει ο μαγνήτης γωνίας και μήκους', () {
        final snap = snapWallPoint(
          raw: const Offset(408, 131),
          walls: const [vertical],
          toleranceCm: 10,
          from: const Offset(400, -100),
        );
        expect(snap.kind, FloorPlanSnapKind.angle);
        expect(near(snap.point, const Offset(400, 130)), isTrue);
      });

      test('άκρη που δεν φαίνεται στην οθόνη δεν δίνει οδηγό', () {
        final snap = snapWallPoint(
          raw: const Offset(450, 4),
          walls: const [horizontal],
          toleranceCm: 10,
          guideEndVisible: (end) => false,
        );
        expect(snap.kind, FloorPlanSnapKind.none);
        expect(snap.point, const Offset(450, 4));
      });

      test('λοξός τοίχος: ο οδηγός ακολουθεί την κατεύθυνσή του, όχι την '
          'οθόνη', () {
        const slanted = FloorPlanSegment(Offset(0, 0), Offset(100, 100));
        final snap = snapWallPoint(
          raw: const Offset(203, 197),
          walls: const [slanted],
          toleranceCm: 10,
        );
        expect(snap.kind, FloorPlanSnapKind.guide);
        expect(near(snap.point, const Offset(200, 200)), isTrue);
      });
    });

    test('με Shift το σημείο μένει όπως είναι', () {
      const walls = [FloorPlanSegment(Offset(0, 0), Offset(300, 0))];
      final snap = snapWallPoint(
        raw: const Offset(303, 4),
        walls: walls,
        toleranceCm: 10,
        from: Offset.zero,
        magnetOff: true,
      );
      expect(snap.kind, FloorPlanSnapKind.none);
      expect(snap.point, const Offset(303, 4));
    });
  });

  group('Μοίρες τομής', () {
    const horizontal = FloorPlanSegment(Offset(0, 0), Offset(300, 0), id: 1);

    test('τοίχος που φεύγει κάθετα από την άκρη άλλου: ορθή γωνία', () {
      final marks = wallJunctionAngles(
        vertex: const Offset(300, 0),
        otherEnd: const Offset(300, 200),
        walls: const [horizontal],
      );
      expect(marks.single.degrees, closeTo(90, 1e-6));
      expect(marks.single.isRight, isTrue);
    });

    test('τοίχος που καταλήγει λοξά στο σώμα άλλου: από τις δύο γωνίες, η '
        'μικρότερη', () {
      // Φτάνει στο (100,0) από κάτω δεξιά, με κλίση 75° ως προς τον τοίχο.
      final rad = 75 * math.pi / 180;
      final marks = wallJunctionAngles(
        vertex: const Offset(100, 0),
        otherEnd: Offset(100 + 200 * math.cos(rad), 200 * math.sin(rad)),
        walls: const [horizontal],
      );
      expect(marks.single.degrees, closeTo(75, 1e-6));
    });

    test('σχεδόν ορθός τοίχος δεν περνά για ορθός', () {
      final marks = wallJunctionAngles(
        vertex: const Offset(300, 0),
        otherEnd: const Offset(298, 200),
        walls: const [horizontal],
      );
      expect(marks.single.isRight, isFalse);
      expect(formatAngleDegrees(marks.single.degrees), '89,4°');
      expect(formatAngleDegrees(90), '90°');
    });

    test('σε γωνία δωματίου δίνει τη γωνία με καθέναν από τους δύο '
        'τοίχους', () {
      const vertical = FloorPlanSegment(
        Offset(300, 0),
        Offset(300, -200),
        id: 2,
      );
      final marks = wallJunctionAngles(
        vertex: const Offset(300, 0),
        otherEnd: const Offset(500, 200),
        walls: const [horizontal, vertical],
      );
      expect(marks.map((m) => m.degrees.round()), [135, 135]);
    });

    test('σε γωνία δωματίου δίνει μία γωνία ανά τοίχο, όταν διαφέρουν', () {
      const vertical = FloorPlanSegment(
        Offset(300, 0),
        Offset(300, -200),
        id: 2,
      );
      final marks = wallJunctionAngles(
        vertex: const Offset(300, 0),
        otherEnd: const Offset(500, 0),
        walls: const [horizontal, vertical],
      );
      expect(marks.map((m) => m.degrees.round()), [180, 90]);
    });

    test('ο ίδιος ο τοίχος δεν μετρά, και τοίχος πάνω σε άλλον δεν δίνει '
        'γωνία', () {
      expect(
        wallJunctionAngles(
          vertex: const Offset(0, 0),
          otherEnd: const Offset(300, 0),
          walls: const [horizontal],
          exceptWallId: 1,
        ),
        isEmpty,
      );
      expect(
        wallJunctionAngles(
          vertex: const Offset(0, 0),
          otherEnd: const Offset(150, 0),
          walls: const [horizontal],
        ),
        isEmpty,
      );
    });

    test('χωρίς τοίχο στο σημείο, δίνει τη γωνία με τον οδηγό πάνω στον '
        'οποίο κάθεται', () {
      // Η προέκταση του οριζόντιου τοίχου, πέρα από το τέλος του.
      const guide = FloorPlanGuide(Offset(300, 0), Offset(1, 0));
      final marks = wallJunctionAngles(
        vertex: const Offset(450, 0),
        otherEnd: const Offset(350, 100),
        walls: const [horizontal],
        guides: const [guide],
      );
      expect(marks.single.toGuide, isTrue);
      expect(marks.single.degrees, closeTo(45, 1e-6));
    });

    test('παχύς τοίχος που ακουμπά στο μάτι τον γείτονα, χωρίς να φτάνει '
        'στη μέση του, δίνει μοίρες', () {
      // Τοίχος 35 εκ. που σταματά 10 εκ. πριν από τη μεσαία γραμμή του
      // οριζόντιου (15 εκ.): η απόληξή του σκεπάζει το σώμα του γείτονα.
      final marks = wallJunctionAngles(
        vertex: const Offset(100, 10),
        otherEnd: const Offset(100, 460),
        walls: const [horizontal],
        thicknessCm: 35,
      );
      expect(marks.single.degrees, closeTo(90, 1e-6));
      expect(marks.single.bodyHalfWidthCm, 17.5);
    });

    test('τοίχος που σταματά πριν ακουμπήσει τον γείτονα δεν δίνει μοίρες', () {
      expect(
        wallJunctionAngles(
          vertex: const Offset(100, 40),
          otherEnd: const Offset(100, 460),
          walls: const [horizontal],
          thicknessCm: 35,
        ),
        isEmpty,
      );
    });

    test('διπλός τοίχος πλάι-πλάι, σχεδόν παράλληλος, δεν δίνει γωνία', () {
      expect(
        wallJunctionAngles(
          vertex: const Offset(0, 12),
          otherEnd: const Offset(300, 13),
          walls: const [horizontal],
        ),
        isEmpty,
      );
    });

    test('σε παχύ τοίχο ο αριθμός βγαίνει έξω από το σώμα του', () {
      const right = FloorPlanAngleMark(
        vertex: Offset.zero,
        armA: Offset(1, 0),
        armB: Offset(0, 1),
        degrees: 90,
        bodyHalfWidthCm: 20,
      );
      // Στη διχοτόμο, η απόσταση από κάθε τοίχο είναι d·ημ45°.
      final d = right.clearanceAlongBisector(20);
      expect(d * math.sin(math.pi / 4), closeTo(20, 1e-9));
      const straight = FloorPlanAngleMark(
        vertex: Offset.zero,
        armA: Offset(1, 0),
        armB: Offset(-1, 0),
        degrees: 180,
      );
      expect(straight.clearanceAlongBisector(20), closeTo(20, 1e-9));
    });
  });

  group('Λαβές μήκους τοίχου', () {
    test('κάθονται έξω από τις άκρες, πάνω στην ευθεία του τοίχου', () {
      final handles = wallEndHandlePoints(
        const Offset(0, 0),
        const Offset(0, 300),
        25,
      );
      expect(handles, [const Offset(0, -25), const Offset(0, 325)]);
    });

    test('κολόνα: οι δύο λαβές δεν πέφτουν η μία πάνω στην άλλη', () {
      // Κολόνα 75 εκ. με μήκος 5 εκ.: οι άκρες απέχουν 5 εκ., οι λαβές
      // πέρα από το πάχος.
      final handles = wallEndHandlePoints(
        const Offset(0, 0),
        const Offset(0, 5),
        37.5 + 10,
      );
      expect((handles[1] - handles[0]).distance, closeTo(100, 1e-9));
      final zero = wallEndHandlePoints(Offset.zero, Offset.zero, 40);
      expect((zero[1] - zero[0]).distance, closeTo(80, 1e-9));
    });

    test('η λαβή που σύρεται φέρνει την άκρη, όχι την ίδια τη λαβή, στο '
        'σημείο', () {
      // Πιάνεται στη θέση της: η άκρη δεν μετακινείται.
      expect(
        wallEndFromHandle(const Offset(0, 325), const Offset(0, 0), 25),
        const Offset(0, 300),
      );
      // Σύρεται πλάγια: η άκρη ακολουθεί πάνω στη νέα ευθεία.
      final end = wallEndFromHandle(const Offset(400, 0), Offset.zero, 25);
      expect(end, const Offset(375, 0));
      // Πιο μέσα από το ίδιο το πάχος: η άκρη μένει στη σταθερή.
      expect(
        wallEndFromHandle(const Offset(0, 10), Offset.zero, 25),
        Offset.zero,
      );
    });

    test('ο τοίχος όπως φαίνεται απλώνει μισό πάχος πέρα από τις άκρες', () {
      final corners = wallOutlineCorners(
        const Offset(0, 0),
        const Offset(100, 0),
        20,
      );
      final xs = corners.map((c) => c.dx);
      final ys = corners.map((c) => c.dy);
      expect(xs.reduce(math.min), -10);
      expect(xs.reduce(math.max), 110);
      expect(ys.reduce(math.min), -10);
      expect(ys.reduce(math.max), 10);
    });
  });

  group('Μήκος σε μέτρα', () {
    test('ελληνική υποδιαστολή και τελεία δίνουν το ίδιο', () {
      expect(parseMetersToCm('4,20'), closeTo(420, 1e-9));
      expect(parseMetersToCm('4.2'), closeTo(420, 1e-9));
    });

    test('κενό, μηδέν, αρνητικό ή κείμενο απορρίπτονται', () {
      expect(parseMetersToCm(''), isNull);
      expect(parseMetersToCm('0'), isNull);
      expect(parseMetersToCm('-3'), isNull);
      expect(parseMetersToCm('τέσσερα'), isNull);
    });

    test('ο τοίχος παίρνει το πληκτρολογημένο μήκος στην κατεύθυνση του '
        'δείκτη', () {
      final p = pointAtLength(Offset.zero, const Offset(0, 37), 420);
      expect(near(p, const Offset(0, 420)), isTrue);
    });

    test('προβολή μήκους', () {
      expect(formatCmAsMeters(420), '4,20 μ.');
    });
  });

  group('Ανοίγματα', () {
    const wall = FloorPlanSegment(Offset(0, 0), Offset(500, 0), id: 1);

    test('το σύρσιμο δίνει αποστάσεις από την αρχή, μικρότερη πρώτη', () {
      final r = openingFromDrag(
        wall,
        const Offset(210, 5),
        const Offset(120, -3),
      );
      expect(r!.start, closeTo(120, 1e-9));
      expect(r.end, closeTo(210, 1e-9));
    });

    test('ένα κλικ χωρίς σύρσιμο δεν ανοίγει τρύπα', () {
      expect(
        openingFromDrag(wall, const Offset(200, 0), const Offset(205, 0)),
        isNull,
      );
    });

    test('ο τοίχος σπάει σε κομμάτια γύρω από τα ανοίγματα', () {
      final pieces = wallPiecesWithOpenings(wall, [
        (start: 100, end: 190),
        (start: 300, end: 380),
      ]);
      expect(pieces.map((s) => (s.a.dx, s.b.dx)).toList(), [
        (0.0, 100.0),
        (190.0, 300.0),
        (380.0, 500.0),
      ]);
    });

    test('άνοιγμα στην άκρη ή επικαλυπτόμενα ανοίγματα', () {
      final pieces = wallPiecesWithOpenings(wall, [
        (start: -50, end: 80),
        (start: 400, end: 450),
        (start: 420, end: 600),
      ]);
      expect(pieces.map((s) => (s.a.dx, s.b.dx)).toList(), [(80.0, 400.0)]);
    });
  });

  group('Ενώσεις γωνιών', () {
    test('διαδοχικοί τοίχοι γίνονται μία συνεχής γραμμή', () {
      final chains = chainSegments(const [
        FloorPlanSegment(Offset(0, 0), Offset(100, 0)),
        FloorPlanSegment(Offset(100, 100), Offset(0, 100)),
        FloorPlanSegment(Offset(100, 0), Offset(100, 100)),
      ]);
      expect(chains, hasLength(1));
      expect(chains.single, hasLength(4));
    });

    test('ξεχωριστοί τοίχοι μένουν ξεχωριστοί', () {
      final chains = chainSegments(const [
        FloorPlanSegment(Offset(0, 0), Offset(100, 0)),
        FloorPlanSegment(Offset(0, 500), Offset(100, 500)),
      ]);
      expect(chains, hasLength(2));
    });
  });

  group('Βαθμονόμηση', () {
    test('ο παχύς τοίχος πιάνεται και από την επιφάνειά του· ο συνηθισμένος '
        'όπως πριν', () {
      const thin = FloorPlanSegment(Offset(0, 0), Offset(400, 0), id: 1);
      const thick = FloorPlanSegment(
        Offset(0, 0),
        Offset(400, 0),
        id: 2,
        thickness: 60,
      );
      // 30 εκ. από τη μέση: μέσα στην ανοχή μόνο για τον τοίχο των 60 εκ.
      expect(nearestWall(const Offset(200, 30), [thin], 10), isNull);
      expect(nearestWall(const Offset(200, 30), [thick], 10)?.id, 2);
    });

    test('τα κομμάτια ενός τοίχου με πόρτα κρατούν το πάχος του', () {
      const thick = FloorPlanSegment(
        Offset(0, 0),
        Offset(400, 0),
        id: 2,
        thickness: 60,
      );
      final pieces = wallPiecesWithOpenings(thick, [
        (start: 100.0, end: 190.0),
      ]);
      expect(pieces.map((p) => p.thickness), [60, 60]);
    });

    test('γραμμή που μετρά 200 αλλά είναι 4 μ. διπλασιάζει την κλίμακα', () {
      expect(
        calibratedCmPerPixel(
          currentCmPerPixel: 1.5,
          measuredCm: 200,
          realCm: 400,
        ),
        closeTo(3, 1e-9),
      );
    });

    test('το σημείο της βαθμονόμησης μένει ακίνητο', () {
      const anchor = Offset(100, 100);
      const center = Offset(300, 100);
      final next = scaleCenterAbout(center: center, anchor: anchor, factor: 2);
      expect(next, const Offset(500, 100));
      // Ένα σημείο της εικόνας πάνω στο anchor απέχει από το κέντρο −200·k.
      expect(next + (anchor - center) * 2, anchor);
    });
  });
}
