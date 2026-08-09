import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/directory/services/user_equipment_codes.dart';
import 'package:flutter_test/flutter_test.dart';

EquipmentModel _equipment({int? id, String? code}) =>
    EquipmentModel(id: id, code: code);

void main() {
  group('Κείμενο στήλης «Εξοπλισμός» υπαλλήλου', () {
    test('ενώνει τους κωδικούς με κόμμα, στη σειρά που δόθηκαν', () {
      final text = UserEquipmentCodes.joinCodes([
        _equipment(id: 1, code: '2792'),
        _equipment(id: 2, code: '3917'),
      ]);

      expect(text, '2792, 3917');
    });

    test('χωρίς εξοπλισμό δίνει κενό κείμενο', () {
      expect(UserEquipmentCodes.joinCodes(const []), '');
    });

    test('κόβει τα κενά γύρω από τον κωδικό', () {
      final text = UserEquipmentCodes.joinCodes([
        _equipment(id: 1, code: '  2792  '),
      ]);

      expect(text, '2792');
    });

    test('εξοπλισμός χωρίς κωδικό πέφτει στον τύπο του', () {
      final text = UserEquipmentCodes.joinCodes([
        _equipment(id: 1, code: '2792'),
        EquipmentModel(id: 7, type: 'Εκτυπωτής'),
      ]);

      expect(text, '2792, Εκτυπωτής');
    });

    test('εξοπλισμός χωρίς κωδικό και χωρίς τύπο παραλείπεται εντελώς', () {
      final text = UserEquipmentCodes.joinCodes([
        _equipment(id: 6, code: '   '),
        _equipment(id: 2, code: '3917'),
      ]);

      expect(text, '3917');
    });
  });

  group('Εξοπλισμός υπαλλήλου χωρίς ταυτότητα', () {
    test('υπάλληλος χωρίς id δεν έχει εξοπλισμό', () {
      expect(UserEquipmentCodes.forUser(null), isEmpty);
      expect(UserEquipmentCodes.textForUser(null), '');
    });
  });
}
