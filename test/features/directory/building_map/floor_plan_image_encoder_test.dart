// Η μετατροπή της εικόνας κάτοψης πριν αποθηκευτεί στη βάση.
//
//   flutter test test/features/directory/building_map/floor_plan_image_encoder_test.dart

import 'dart:typed_data';

import 'package:call_logger/features/directory/building_map/services/floor_plan_image_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Uint8List png(img.Image image) => img.encodePng(image);

  test('οι διαστάσεις δεν αλλάζουν — οι θέσεις των τμημάτων είναι ποσοστά '
      'της εικόνας', () {
    final source = img.Image(width: 37, height: 21);
    img.fill(source, color: img.ColorRgb8(120, 120, 120));

    final out = img.decodeJpg(encodeFloorPlanImage(png(source)))!;

    expect(out.width, 37);
    expect(out.height, 21);
  });

  test('τα διάφανα σημεία γίνονται λευκά, όχι μαύρα', () {
    final source = img.Image(width: 8, height: 8, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(0, 0, 0, 0));

    final out = img.decodeJpg(encodeFloorPlanImage(png(source)))!;
    final pixel = out.getPixel(4, 4);

    expect(pixel.r, greaterThan(240));
    expect(pixel.g, greaterThan(240));
    expect(pixel.b, greaterThan(240));
  });

  test('αρχείο που δεν είναι εικόνα: σαφές σφάλμα', () {
    expect(
      () => encodeFloorPlanImage(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<FloorPlanImageUnreadable>()),
    );
  });
}
