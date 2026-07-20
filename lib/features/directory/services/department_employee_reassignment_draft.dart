import '../screens/widgets/department_employee_reassign_dialog.dart';
import '../screens/widgets/shared_asset_disconnect_dialog.dart';

/// Σταδιακή ανάθεση υπαλλήλων σε τμήματα προορισμού (χωρίς UI).
class EmployeeReassignmentDraft {
  EmployeeReassignmentDraft(List<DepartmentEmployeeReassignCandidate> employees)
      : _employees = List<DepartmentEmployeeReassignCandidate>.unmodifiable(
          employees,
        );

  final List<DepartmentEmployeeReassignCandidate> _employees;
  final Map<int, SharedAssetTransferTarget> _assignments = {};

  /// Υπάλληλοι που δεν έχουν ανατεθεί ακόμη (σειρά εισόδου).
  List<DepartmentEmployeeReassignCandidate> get remaining => [
        for (final e in _employees)
          if (!_assignments.containsKey(e.id)) e,
      ];

  int get remainingCount => remaining.length;

  int get assignedCount => _assignments.length;

  bool get isComplete => remainingCount == 0;

  /// Τρέχουσες αναθέσεις (για εμφάνιση προόδου στο UI).
  Map<int, SharedAssetTransferTarget> get assignments =>
      Map.unmodifiable(_assignments);

  /// Αναθέτει στον [target] όσους από τους [ids] είναι ακόμη στο remaining.
  void assign(Set<int> ids, SharedAssetTransferTarget target) {
    if (ids.isEmpty) return;
    for (final id in ids) {
      if (_assignments.containsKey(id)) continue;
      final known = _employees.any((e) => e.id == id);
      if (!known) continue;
      _assignments[id] = target;
    }
  }

  DepartmentEmployeeReassignBatch build() =>
      DepartmentEmployeeReassignBatch(transfers: Map.of(_assignments));
}
