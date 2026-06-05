import 'package:call_logger/core/database/old_database/equipment_set_master_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('findEquipmentSetMasterCycleRoots', () {
    test('detects self-loop as cycle root', () {
      expect(
        findEquipmentSetMasterCycleRoots(<int, int>{17: 17}),
        {17},
      );
    });

    test('detects two-node cycle', () {
      expect(
        findEquipmentSetMasterCycleRoots(<int, int>{17: 18, 18: 17}),
        {17, 18},
      );
    });

    test('ignores acyclic chain', () {
      expect(
        findEquipmentSetMasterCycleRoots(<int, int>{1: 2, 2: 3}),
        isEmpty,
      );
    });
  });
}
