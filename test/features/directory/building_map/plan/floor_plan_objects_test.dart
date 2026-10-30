// Η γεωμετρία των αντικειμένων του χάρτη: τι πιάνει το ποντίκι, τι χωρά στο
// ορθογώνιο επιλογής, και πώς γυρίζουν και αλλάζουν μέγεθος.
//
//   flutter test test/features/directory/building_map/plan/floor_plan_objects_test.dart

import 'dart:ui' show Offset, Rect, Size;

import 'package:call_logger/core/models/floor_plan_object.dart';
import 'package:call_logger/core/models/floor_plan_object_kind.dart';
import 'package:call_logger/features/directory/building_map/plan/floor_plan_objects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const printerKind = FloorPlanObjectKind(
    id: 1,
    name: 'Εκτυπωτής',
    symbol: FloorPlanSymbol.printer,
  );
  const deskKind = FloorPlanObjectKind(
    id: 2,
    name: 'Γραφείο',
    symbol: FloorPlanSymbol.furniture,
  );
  final kinds = {1: printerKind, 2: deskKind};

  FloorPlanObject object(
    int id,
    int kindId,
    Offset center, {
    Size? size,
    double rotation = 0,
  }) => FloorPlanObject(
    id: id,
    floorId: 1,
    kindId: kindId,
    center: center,
    size: size,
    rotationDegrees: rotation,
  );

  Matcher near(Offset expected) => predicate<Offset>(
    (p) => (p - expected).distance < 0.01,
    'κοντά στο $expected',
  );

  group('Ποιο αντικείμενο πιάνει το κλικ', () {
    final desk = object(1, 2, Offset.zero, size: const Size(160, 80));
    final printer = object(2, 1, const Offset(40, 0));
    final views = buildFloorPlanObjectViews([printer, desk], kinds);

    test('τα έπιπλα μπαίνουν πρώτα, για να ζωγραφίζονται από κάτω', () {
      expect([for (final v in views) v.id], [1, 2]);
    });

    test('κλικ στον εκτυπωτή πάνω στο γραφείο πιάνει τον εκτυπωτή', () {
      expect(hitTestFloorPlanObject(const Offset(45, 5), views)?.id, 2);
    });

    test('κλικ στο ελεύθερο μέρος του γραφείου πιάνει το γραφείο', () {
      expect(hitTestFloorPlanObject(const Offset(-60, 20), views)?.id, 1);
    });

    test('κλικ έξω από όλα δεν πιάνει τίποτα', () {
      expect(hitTestFloorPlanObject(const Offset(300, 0), views), isNull);
    });

    test('το ορθογώνιο επιλογής πιάνει μόνο ό,τι χωρά ολόκληρο', () {
      final rect = Rect.fromLTRB(0, -50, 100, 50);
      expect(floorPlanObjectsInside(rect.contains, views), {2});
    });
  });

  test('έπιπλο χωρίς αποθηκευμένο μέγεθος παίρνει το τετράγωνο συμβόλου', () {
    final view = buildFloorPlanObjectViews([
      object(1, 2, Offset.zero),
    ], kinds).single;
    expect(view.size, const Size.square(kFloorPlanSymbolSizeCm));
  });

  test('η περιστροφή γύρω από άλλο σημείο μετακινεί και γυρίζει το '
      'αντικείμενο', () {
    final rotated = rotateFloorPlanObject(
      object(1, 1, const Offset(100, 0)),
      Offset.zero,
      3.141592653589793 / 2,
    );
    expect(rotated.center, near(const Offset(0, 100)));
    expect(rotated.rotationDegrees, closeTo(90, 1e-9));
  });

  group('Αλλαγή μεγέθους επίπλου', () {
    test('η απέναντι γωνία μένει ακίνητη', () {
      final desk = object(1, 2, Offset.zero, size: const Size(160, 80));
      // Σέρνεται η κάτω δεξιά γωνία (80, 40) στο (120, 60).
      final resized = resizeFloorPlanVolume(
        desk,
        desk.size!,
        2,
        const Offset(120, 60),
      );
      expect(resized.size, const Size(200, 100));
      final corners = rotatedRectCorners(
        resized.center,
        resized.size!,
        resized.rotationDegrees,
      );
      expect(corners[0], near(const Offset(-80, -40)));
    });

    test('σε γυρισμένο έπιπλο το μέγεθος μετριέται κατά μήκος του', () {
      final desk = object(
        1,
        2,
        Offset.zero,
        size: const Size(160, 80),
        rotation: 90,
      );
      final corners = rotatedRectCorners(Offset.zero, desk.size!, 90);
      final resized = resizeFloorPlanVolume(
        desk,
        desk.size!,
        2,
        corners[2] + const Offset(0, 40),
      );
      expect(resized.size!.width, closeTo(200, 0.01));
      expect(resized.size!.height, closeTo(80, 0.01));
      final after = rotatedRectCorners(resized.center, resized.size!, 90);
      expect(after[0], near(corners[0]));
    });

    test('δεν μικραίνει κάτω από το ελάχιστο', () {
      final desk = object(1, 2, Offset.zero, size: const Size(160, 80));
      final resized = resizeFloorPlanVolume(
        desk,
        desk.size!,
        2,
        const Offset(-80, -40),
      );
      expect(resized.size, const Size.square(kFloorPlanMinVolumeCm));
    });
  });

  test('έπιπλο από δύο γωνίες, σε οποιαδήποτε σειρά', () {
    final volume = floorPlanVolumeFromCorners(
      const Offset(160, 80),
      Offset.zero,
    );
    expect(volume.center, const Offset(80, 40));
    expect(volume.size, const Size(160, 80));
  });

  test('πληκτρολογημένες διαστάσεις μετρούν προς την πλευρά του δείκτη', () {
    final volume = floorPlanVolumeToward(
      Offset.zero,
      const Offset(-10, 30),
      const Size(160, 80),
    );
    expect(volume.center, const Offset(-80, 40));
    expect(volume.size, const Size(160, 80));
  });

  group('Πληκτρολόγηση διαστάσεων', () {
    test('δέχεται κόμμα, τελεία, x, * και κενό', () {
      for (final text in ['1,60 x 0,80', '1.6*0.8', '1,6 0,8', '1,60Χ0,80']) {
        expect(parseVolumeSizeMeters(text), const Size(160, 80), reason: text);
      }
    });

    test('ένας αριθμός ή μηδέν δεν είναι διαστάσεις', () {
      expect(parseVolumeSizeMeters('1,60'), isNull);
      expect(parseVolumeSizeMeters('0 x 0,8'), isNull);
      expect(parseVolumeSizeMeters(''), isNull);
    });
  });

  test('από μακριά μένουν μόνο τα έπιπλα — ό,τι δεν φαίνεται δεν πιάνεται', () {
    final views = buildFloorPlanObjectViews([
      object(1, 2, Offset.zero, size: const Size(160, 80)),
      object(2, 1, Offset.zero),
    ], kinds);

    final far = floorPlanObjectsAtZoom(views, 0.1);
    expect([for (final v in far) v.id], [1]);
    expect(hitTestFloorPlanObject(Offset.zero, far)?.id, 1);

    final near = floorPlanObjectsAtZoom(views, 1);
    expect(near, hasLength(2));
  });

  test('ό,τι είναι μέσα σε καμπίνα δεν ζωγραφίζεται στον χάρτη', () {
    final views = buildFloorPlanObjectViews([
      object(1, 1, Offset.zero),
      FloorPlanObject(
        id: 2,
        floorId: 1,
        kindId: 1,
        center: Offset.zero,
        cabinetId: 9,
        rackU: 1,
      ),
    ], kinds);
    expect(views.map((v) => v.id), [1]);
  });
}
