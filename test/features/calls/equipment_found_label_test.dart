import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_phone_presentational.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('equipmentFoundLabel', () {
    test('ενικός — 1 εξοπλισμός', () {
      expect(equipmentFoundLabel(1), 'Βρέθηκε 1 εξοπλισμός');
    });

    test('πληθυντικός — 2 εξοπλισμοί', () {
      expect(equipmentFoundLabel(2), 'Βρέθηκαν 2 εξοπλισμοί');
    });
  });
}
