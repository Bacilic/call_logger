import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_state.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/settings/widgets/start_from_beginning_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hasOpenCallSession', () {
    final emptyEntry = CallEntryState();
    final emptyHeader = SmartEntitySelectorState();

    test('εντελώς κενή φόρμα → false', () {
      expect(hasOpenCallSession(emptyEntry, emptyHeader), isFalse);
    });

    test('μόνο callerDisplayText συμπληρωμένο → true', () {
      final header = SmartEntitySelectorState(callerDisplayText: 'Γιάννης');
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο equipmentText συμπληρωμένο → true', () {
      final header = SmartEntitySelectorState(equipmentText: 'PC-01');
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο selectedCaller → true', () {
      final header = SmartEntitySelectorState(
        selectedCaller: UserModel(id: 1, firstName: 'Test'),
      );
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο selectedPhone → true', () {
      final header = SmartEntitySelectorState(selectedPhone: '2262');
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο departmentText → true', () {
      final header = SmartEntitySelectorState(departmentText: 'IT');
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('μόνο selectedEquipment → true', () {
      final header = SmartEntitySelectorState(
        selectedEquipment: EquipmentModel(id: 5, code: 'EQ-1'),
      );
      expect(hasOpenCallSession(emptyEntry, header), isTrue);
    });

    test('entry.notes → true', () {
      final entry = CallEntryState(notes: 'πρόβλημα δικτύου');
      expect(hasOpenCallSession(entry, emptyHeader), isTrue);
    });

    test('entry.isCallTimerRunning → true', () {
      final entry = CallEntryState(isCallTimerRunning: true);
      expect(hasOpenCallSession(entry, emptyHeader), isTrue);
    });
  });
}
