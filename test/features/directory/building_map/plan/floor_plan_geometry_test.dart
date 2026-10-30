// Η γεωμετρία της σχεδίασης τοίχων: μαγνήτης, ανοίγματα, ενώσεις γωνιών,
// βαθμονόμηση, πληκτρολόγηση μήκους.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_geometry_test.dart

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
        raw: const Offset(150, 6),
        walls: walls,
        toleranceCm: 10,
      );
      expect(snap.kind, FloorPlanSnapKind.wallBody);
      expect(snap.point, const Offset(150, 0));
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
