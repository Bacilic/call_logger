// Unit tests: πού βρίσκεται ένας εξοπλισμός — κληρονομιά από τον κάτοχο και
// σύνθεση της στήλης «Τοποθεσία».
//
//   flutter test test/features/directory/equipment_location_inheritance_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/models/equipment_column.dart';
import 'package:flutter_test/flutter_test.dart';

EquipmentRow rowWith({String? equipmentLocation, String? ownerLocation}) => (
  EquipmentModel(
    id: 1,
    code: '3601',
    departmentId: 7,
    location: equipmentLocation,
  ),
  ownerLocation == null && equipmentLocation != null
      ? null
      : UserModel(
          id: 5,
          firstName: 'Άννα',
          lastName: 'Πατσαρίκα',
          departmentId: 7,
          location: ownerLocation,
        ),
);

void main() {
  group('effectiveEquipmentLocation', () {
    test('χωρίς κάτοχο ισχύει η τοποθεσία του εξοπλισμού', () {
      final row = (
        EquipmentModel(id: 1, location: 'ράφι 3'),
        null as UserModel?,
      );

      expect(effectiveEquipmentLocation(row), 'ράφι 3');
    });

    test('με κάτοχο και κενό δικό του πεδίο, κληρονομεί από τον κάτοχο', () {
      final row = rowWith(ownerLocation: 'κάτω από το παράθυρο');

      expect(
        effectiveEquipmentLocation(row),
        'κάτω από το παράθυρο',
      );
    });

    test('η ρητή τοποθεσία του εξοπλισμού υπερισχύει του κατόχου', () {
      final row = rowWith(
        equipmentLocation: 'δίπλα στον εκτυπωτή',
        ownerLocation: 'πίσω από την πόρτα',
      );

      expect(effectiveEquipmentLocation(row), 'δίπλα στον εκτυπωτή');
    });

    test('κενά διαστήματα δεν μετρούν ως ρητή τοποθεσία', () {
      final row = rowWith(
        equipmentLocation: '   ',
        ownerLocation: 'πίσω από την πόρτα',
      );

      expect(effectiveEquipmentLocation(row), 'πίσω από την πόρτα');
    });

    test('χωρίς καμία πηγή επιστρέφει κενό', () {
      final row = rowWith(ownerLocation: null);

      expect(effectiveEquipmentLocation(row), '');
    });
  });

  group('equipmentLocationDivergenceNotice', () {
    test('ονομάζει τον κάτοχο και τη θέση που αφήνει πίσω', () {
      expect(
        equipmentLocationDivergenceNotice(
          ownerName: 'Άννα Πατσαρίκα',
          ownerLocation: 'πρώτο θρανίο δεξιά',
        ),
        'Δεν ακολουθεί τον κάτοχο — ο/η Άννα Πατσαρίκα είναι «πρώτο θρανίο δεξιά»',
      );
    });

    test('όταν ο κάτοχος δεν έχει θέση, το λέει ρητά', () {
      expect(
        equipmentLocationDivergenceNotice(
          ownerName: 'Άννα Πατσαρίκα',
          ownerLocation: null,
        ),
        'Δεν ακολουθεί τον κάτοχο — ο/η Άννα Πατσαρίκα δεν έχει ορίσει θέση',
      );
      expect(
        equipmentLocationDivergenceNotice(
          ownerName: 'Άννα Πατσαρίκα',
          ownerLocation: '   ',
        ),
        'Δεν ακολουθεί τον κάτοχο — ο/η Άννα Πατσαρίκα δεν έχει ορίσει θέση',
      );
    });

    test('χωρίς όνομα κατόχου δεν μένει κενό στη μέση της πρότασης', () {
      expect(
        equipmentLocationDivergenceNotice(
          ownerName: '  ',
          ownerLocation: 'πρώτο θρανίο δεξιά',
        ),
        'Δεν ακολουθεί τον κάτοχο — ο κάτοχος είναι «πρώτο θρανίο δεξιά»',
      );
    });
  });

  group('equipmentRowLocationFormattedLine', () {
    setUp(() {
      LookupService.instance.departments = [
        DepartmentModel(
          id: 7,
          name: 'Πληροφορική',
          building: 'Νέο',
          floorId: 3,
        ),
      ];
      LookupService.instance.departmentIdToName = {7: 'Πληροφορική'};
      LookupService.instance.floorLabelById = {3: '1ος'};
    });

    tearDown(() {
      LookupService.instance.departments = [];
      LookupService.instance.departmentIdToName = {};
      LookupService.instance.floorLabelById = {};
    });

    test('συνθέτει κτίριο, όροφο, τμήμα και τοποθεσία', () {
      final row = rowWith(ownerLocation: 'πίσω από την πόρτα');

      expect(
        equipmentRowLocationFormattedLine(row),
        '[Νέο 1ος] Πληροφορική - πίσω από την πόρτα',
      );
    });

    test('χωρίς όροφο μένει μόνο το κτίριο', () {
      LookupService.instance.floorLabelById = {};
      final row = rowWith(ownerLocation: 'πίσω από την πόρτα');

      expect(
        equipmentRowLocationFormattedLine(row),
        '[Νέο] Πληροφορική - πίσω από την πόρτα',
      );
    });

    test('η ρητή τοποθεσία του εξοπλισμού φαίνεται στη στήλη', () {
      final row = rowWith(
        equipmentLocation: 'δίπλα στον εκτυπωτή',
        ownerLocation: 'πίσω από την πόρτα',
      );

      expect(
        equipmentRowLocationFormattedLine(row),
        '[Νέο 1ος] Πληροφορική - δίπλα στον εκτυπωτή',
      );
    });

    test('χωρίς τοποθεσία μένουν κτίριο, όροφος και τμήμα', () {
      final row = rowWith(ownerLocation: null);

      expect(equipmentRowLocationFormattedLine(row), '[Νέο 1ος] Πληροφορική');
    });

    test('με showBuilding: false παραλείπεται το πρόθεμα', () {
      final row = rowWith(ownerLocation: 'πίσω από την πόρτα');

      expect(
        equipmentRowLocationFormattedLine(row, showBuilding: false),
        'Πληροφορική - πίσω από την πόρτα',
      );
    });
  });
}
