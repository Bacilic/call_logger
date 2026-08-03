import 'package:call_logger/features/audit/models/audit_log_model.dart';
import 'package:call_logger/features/audit/services/audit_reference_label_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditReferenceLabelResolver.collectDepartmentIds', () {
    test('συλλέγει department_id από old/new JSON', () {
      final row = AuditLogModel(
        id: 1,
        oldValuesJson: '{"department_id":10}',
        newValuesJson: '{"department_id":20}',
      );
      final ids = <int>{};
      AuditReferenceLabelResolver.collectDepartmentIds(row, ids);
      expect(ids, {10, 20});
    });

    test('συλλέγει department_id από bulk JSON', () {
      final row = AuditLogModel(
        id: 2,
        newValuesJson: '{"fields":{"department_id":5},"affected_ids":[1,2,3]}',
      );
      final ids = <int>{};
      AuditReferenceLabelResolver.collectDepartmentIds(row, ids);
      expect(ids, {5});
    });
  });

  group('AuditReferenceLabelResolver.collectUserIds', () {
    test('συλλέγει linked_user_id από old/new JSON', () {
      final row = AuditLogModel(
        id: 3,
        oldValuesJson: '{"linked_user_id":243}',
        newValuesJson: '{"linked_user_id":7}',
      );
      final ids = <int>{};
      AuditReferenceLabelResolver.collectUserIds(row, ids);
      expect(ids, {243, 7});
    });

    test('συλλέγει linked_user_id από bulk fields JSON', () {
      final row = AuditLogModel(
        id: 4,
        newValuesJson: '{"fields":{"linked_user_id":9},"affected_ids":[1]}',
      );
      final ids = <int>{};
      AuditReferenceLabelResolver.collectUserIds(row, ids);
      expect(ids, {9});
    });
  });
}
