import 'package:call_logger/features/directory/screens/widgets/department_employee_reassign_dialog.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/department_employee_reassignment_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const candidates = [
    DepartmentEmployeeReassignCandidate(id: 1, name: 'Άλφα'),
    DepartmentEmployeeReassignCandidate(id: 2, name: 'Βήτα'),
    DepartmentEmployeeReassignCandidate(id: 3, name: 'Γάμμα'),
  ];

  group('EmployeeReassignmentDraft', () {
    test('ανάθεση υποσυνόλου μειώνει remaining και αυξάνει assignedCount', () {
      final draft = EmployeeReassignmentDraft(candidates);
      expect(draft.remainingCount, 3);
      expect(draft.assignedCount, 0);
      expect(draft.isComplete, isFalse);

      draft.assign(
        {1, 2},
        const SharedAssetTransferTarget.existing(10),
      );

      expect(draft.remainingCount, 1);
      expect(draft.assignedCount, 2);
      expect(draft.remaining.map((e) => e.id), [3]);
      expect(draft.isComplete, isFalse);
    });

    test('δεύτερη ανάθεση υπολοίπων → isComplete true', () {
      final draft = EmployeeReassignmentDraft(candidates);
      draft.assign({1}, const SharedAssetTransferTarget.existing(10));
      draft.assign(
        {2, 3},
        const SharedAssetTransferTarget.createNew('Νέο'),
      );

      expect(draft.remainingCount, 0);
      expect(draft.assignedCount, 3);
      expect(draft.isComplete, isTrue);
    });

    test('build() επιστρέφει σωστό Map userId → target', () {
      final draft = EmployeeReassignmentDraft(candidates);
      const existing = SharedAssetTransferTarget.existing(42);
      const created = SharedAssetTransferTarget.createNew('Νέο Τμήμα');
      draft.assign({1, 3}, existing);
      draft.assign({2}, created);

      final batch = draft.build();
      expect(batch.transfers[1], existing);
      expect(batch.transfers[2], created);
      expect(batch.transfers[3], existing);
      expect(batch.transfers.length, 3);
    });

    test('ids εκτός λίστας ή διπλή ανάθεση δεν χαλούν την κατάσταση', () {
      final draft = EmployeeReassignmentDraft(candidates);
      const target = SharedAssetTransferTarget.existing(7);
      draft.assign({1, 99}, target);
      expect(draft.assignedCount, 1);
      expect(draft.remaining.map((e) => e.id), [2, 3]);

      draft.assign({1}, const SharedAssetTransferTarget.existing(8));
      expect(draft.assignedCount, 1);
      expect(draft.build().transfers[1]?.departmentId, 7);
    });

    test('κενό set δεν αλλάζει τίποτα', () {
      final draft = EmployeeReassignmentDraft(candidates);
      draft.assign({}, const SharedAssetTransferTarget.existing(1));
      expect(draft.remainingCount, 3);
      expect(draft.assignedCount, 0);
      expect(draft.build().transfers, isEmpty);
    });
  });
}
