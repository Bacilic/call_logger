// Τι προειδοποιεί ο χρήστης ότι θα χάσει όταν μια καρτέλα φεύγει από την κάτοψη.
//
// Η προειδοποίηση εμφανίζεται ΜΟΝΟ όταν υπάρχει κάτι να χαθεί, και απαριθμεί
// μόνο ό,τι υπάρχει — ποτέ υπόσχεση διαγραφής για πεδίο που είναι ήδη κενό.
//
//   flutter test test/features/directory/building_map_placement_loss_test.dart

import 'package:call_logger/features/directory/services/building_map_placement_loss.dart';
import 'package:flutter_test/flutter_test.dart';

BuildingMapPlacementLoss _loss({
  bool kindBelongsOnMap = false,
  String? building = 'Καινούριο',
  String? floorLabel = '3ος - Χειρουργική-Ορθοπαιδική-Διοικητής',
  double? mapWidth,
  double? mapHeight,
}) {
  return judgeBuildingMapPlacementLoss(
    kindBelongsOnMap: kindBelongsOnMap,
    building: building,
    floorLabel: floorLabel,
    mapWidth: mapWidth,
    mapHeight: mapHeight,
  );
}

void main() {
  group('Πότε ρωτιέται ο χρήστης', () {
    test('τμήμα νοσοκομείου: ποτέ — τίποτα δεν φεύγει', () {
      final loss = _loss(kindBelongsOnMap: true, mapWidth: 120, mapHeight: 80);

      expect(loss.hasAnything, isFalse);
    });

    test('εταιρεία χωρίς κτίριο, όροφο ή σχήμα: καμία ερώτηση', () {
      final loss = _loss(building: null, floorLabel: null);

      expect(
        loss.hasAnything,
        isFalse,
        reason: 'οι CCS, Evorad και DataMed δεν βλέπουν ποτέ τον διάλογο',
      );
    });

    test('εταιρεία με κτίριο και όροφο: ερώτηση', () {
      expect(_loss().hasAnything, isTrue);
    });

    test('μόνο το σχήμα αρκεί για ερώτηση', () {
      final loss = _loss(
        building: null,
        floorLabel: null,
        mapWidth: 120,
        mapHeight: 80,
      );

      expect(loss.hasAnything, isTrue);
      expect(loss.hasShape, isTrue);
    });

    test('μηδενικές διαστάσεις δεν είναι σχήμα', () {
      final loss = _loss(
        building: null,
        floorLabel: null,
        mapWidth: 0,
        mapHeight: 0,
      );

      expect(
        loss.hasShape,
        isFalse,
        reason: 'το μηδέν σημαίνει «δεν σχεδιάστηκε ποτέ»',
      );
      expect(loss.hasAnything, isFalse);
    });

    test('κενά κείμενα μετρούν ως ανύπαρκτα', () {
      final loss = _loss(building: '   ', floorLabel: '');

      expect(loss.hasAnything, isFalse);
    });
  });

  group('Το μήνυμα απαριθμεί μόνο ό,τι υπάρχει', () {
    test('κτίριο και όροφος, χωρίς σχήμα', () {
      final message = buildingMapPlacementLossMessage(
        departmentName: 'Αναισθησιολογικό',
        kindLabel: 'Εταιρεία',
        loss: _loss(),
      );

      expect(message, contains('«Αναισθησιολογικό»'));
      expect(message, contains('«Εταιρεία»'));
      expect(message, contains('• Κτίριο: Καινούριο'));
      expect(message, contains('• Όροφος: 3ος'));
      expect(
        message,
        isNot(contains('θέση στην κάτοψη')),
        reason: 'δεν υπόσχεται διαγραφή σχήματος που δεν υπάρχει',
      );
    });

    test('μόνο σχήμα', () {
      final message = buildingMapPlacementLossMessage(
        departmentName: 'Αξονικός',
        kindLabel: 'Εξωτερική μονάδα',
        loss: _loss(
          building: null,
          floorLabel: null,
          mapWidth: 120,
          mapHeight: 80,
        ),
      );

      expect(message, contains('• Η θέση στην κάτοψη'));
      expect(message, isNot(contains('• Κτίριο')));
      expect(message, isNot(contains('• Όροφος')));
    });

    test('το όνομα μένει άκλιτο μέσα στα εισαγωγικά του', () {
      final message = buildingMapPlacementLossMessage(
        departmentName: 'Γραμματεία ΤΕΠ',
        kindLabel: 'Εταιρεία',
        loss: _loss(),
      );

      expect(message, contains('Η καρτέλα «Γραμματεία ΤΕΠ»'));
    });
  });
}
