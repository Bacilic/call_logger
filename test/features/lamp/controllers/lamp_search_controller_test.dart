import 'package:call_logger/features/lamp/controllers/lamp_search_controller.dart';
import 'package:call_logger/features/lamp/widgets/lamp_result_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LampSearchController.buildResultViewModels', () {
    test('επιστρέφει EquipmentViewModel ένα-προς-ένα για κάθε γραμμή', () {
      const rows = <Map<String, Object?>>[
        <String, Object?>{
          'code': 1001,
          'description': 'Εκτυπωτής Laser A3',
          'serial_no': 'SN123456789',
        },
        <String, Object?>{
          'code': 2002,
          'description': 'Switch δικτύου',
          'serial_no': 'SN-2002',
        },
      ];

      final viewModels = LampSearchController.buildResultViewModels(rows);

      expect(viewModels, hasLength(2));
      expect(viewModels[0], isA<EquipmentViewModel>());
      expect(viewModels[1], isA<EquipmentViewModel>());
      expect(viewModels[0].sourceRow['code'], 1001);
      expect(viewModels[0].sourceRow['description'], 'Εκτυπωτής Laser A3');
      expect(viewModels[1].sourceRow['code'], 2002);
      expect(viewModels[1].sourceRow['description'], 'Switch δικτύου');
    });

    test('κενή λίστα γραμμών επιστρέφει κενή λίστα view models', () {
      final viewModels = LampSearchController.buildResultViewModels(
        const <Map<String, Object?>>[],
      );

      expect(viewModels, isEmpty);
    });
  });
}
