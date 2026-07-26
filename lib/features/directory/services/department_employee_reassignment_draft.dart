import '../screens/widgets/department_employee_reassign_dialog.dart';
import '../screens/widgets/shared_asset_disconnect_dialog.dart';

/// Σταδιακή απόφαση για υπαλλήλους: μεταφορά σε τμήμα προορισμού ή διαγραφή (χωρίς UI).
class EmployeeReassignmentDraft {
  EmployeeReassignmentDraft(List<DepartmentEmployeeReassignCandidate> employees)
    : _employees = List<DepartmentEmployeeReassignCandidate>.unmodifiable(
        employees,
      );

  final List<DepartmentEmployeeReassignCandidate> _employees;
  final Map<int, SharedAssetTransferTarget> _assignments = {};
  final Set<int> _toDelete = {};

  /// Υπάλληλοι χωρίς απόφαση ακόμη (ούτε μεταφορά ούτε διαγραφή, σειρά εισόδου).
  List<DepartmentEmployeeReassignCandidate> get remaining => [
    for (final e in _employees)
      if (!_assignments.containsKey(e.id) && !_toDelete.contains(e.id)) e,
  ];

  int get remainingCount => remaining.length;

  int get assignedCount => _assignments.length;

  int get deletionCount => _toDelete.length;

  bool get isComplete => remainingCount == 0;

  /// Τρέχουσες αναθέσεις μεταφοράς (για εμφάνιση προόδου στο UI).
  Map<int, SharedAssetTransferTarget> get assignments =>
      Map.unmodifiable(_assignments);

  /// Υπάλληλοι μαρκαρισμένοι προς διαγραφή.
  Set<int> get toDelete => Set.unmodifiable(_toDelete);

  /// Αναθέτει στον [target] όσους από τους [ids] είναι ακόμη στο remaining.
  void assign(Set<int> ids, SharedAssetTransferTarget target) {
    if (ids.isEmpty) return;
    for (final id in ids) {
      if (_assignments.containsKey(id) || _toDelete.contains(id)) continue;
      final known = _employees.any((e) => e.id == id);
      if (!known) continue;
      _assignments[id] = target;
    }
  }

  /// Μαρκάρει προς διαγραφή όσους από τους [ids] είναι ακόμη στο remaining.
  void markForDeletion(Set<int> ids) {
    if (ids.isEmpty) return;
    for (final id in ids) {
      if (_assignments.containsKey(id) || _toDelete.contains(id)) continue;
      final known = _employees.any((e) => e.id == id);
      if (!known) continue;
      _toDelete.add(id);
    }
  }

  DepartmentEmployeeReassignBatch build() => DepartmentEmployeeReassignBatch(
    transfers: Map.of(_assignments),
    toDelete: Set.of(_toDelete),
  );
}
