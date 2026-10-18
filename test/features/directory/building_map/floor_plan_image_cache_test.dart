// Το τοπικό αντίγραφο της κάτοψης σε κάθε σταθμό.
//
//   flutter test test/features/directory/building_map/floor_plan_image_cache_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:call_logger/core/database/building_map_repository.dart';
import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/features/directory/building_map/services/floor_plan_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late int loads;
  late ({Uint8List bytes, String hash})? stored;
  late FloorPlanImageCache cache;

  BuildingMapFloor floor(String? hash) => BuildingMapFloor(
    id: 1,
    sortOrder: 0,
    label: '2ος',
    imagePath: '',
    rotationDegrees: 0,
    imageHash: hash,
  );

  ({Uint8List bytes, String hash}) image(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    return (bytes: data, hash: floorImageHash(data));
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('floor_plan_cache_');
    loads = 0;
    stored = null;
    cache = FloorPlanImageCache(
      directory: () async => dir.path,
      loadImage: (_) async {
        loads++;
        return stored;
      },
    );
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'κάτοψη που δεν ανέβηκε: κανένα αρχείο, καμία ερώτηση στη βάση',
    () async {
      expect(await cache.fileFor(floor(null)), isNull);
      expect(loads, 0);
    },
  );

  test('η εικόνα κατεβαίνει μία φορά· μετά διαβάζεται από τον δίσκο', () async {
    stored = image([1, 2, 3]);

    final first = await cache.fileFor(floor(stored!.hash));
    final second = await cache.fileFor(floor(stored!.hash));

    expect(await first!.readAsBytes(), [1, 2, 3]);
    expect(second!.path, first.path);
    expect(loads, 1);
  });

  test('ταυτόχρονα αιτήματα για την ίδια εικόνα: μία λήψη', () async {
    stored = image([9, 9]);
    final results = await Future.wait([
      cache.fileFor(floor(stored!.hash)),
      cache.fileFor(floor(stored!.hash)),
    ]);
    expect(results[0]!.path, results[1]!.path);
    expect(loads, 1);
  });

  test('νέα εικόνα στη βάση (νέο αποτύπωμα): κατεβαίνει η νέα', () async {
    stored = image([1]);
    await cache.fileFor(floor(stored!.hash));
    stored = image([2]);

    final file = await cache.fileFor(floor(stored!.hash));

    expect(await file!.readAsBytes(), [2]);
    expect(loads, 2);
  });

  test('η βάση δεν απαντά: κανένα αρχείο, χωρίς να πέσει η εφαρμογή', () async {
    cache = FloorPlanImageCache(
      directory: () async => dir.path,
      loadImage: (_) async => throw const FileSystemException('δίκτυο'),
    );
    expect(await cache.fileFor(floor('abc')), isNull);
  });
}
