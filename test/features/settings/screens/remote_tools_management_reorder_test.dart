import 'package:call_logger/features/settings/screens/remote_tools_management_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reorderedPositionOneBased', () {
    test('μετακίνηση προς τα κάτω: newIndex > oldIndex αφαιρεί 1', () {
      expect(reorderedPositionOneBased(0, 2), 2);
      expect(reorderedPositionOneBased(0, 4), 4);
      expect(reorderedPositionOneBased(1, 3), 3);
    });

    test('μετακίνηση προς τα πάνω: newIndex <= oldIndex → newIndex + 1', () {
      expect(reorderedPositionOneBased(3, 0), 1);
      expect(reorderedPositionOneBased(2, 1), 2);
      expect(reorderedPositionOneBased(2, 2), 3);
    });

    test('από αρχή στο τέλος και αντίστροφα', () {
      expect(reorderedPositionOneBased(0, 5), 5);
      expect(reorderedPositionOneBased(4, 0), 1);
    });
  });
}
