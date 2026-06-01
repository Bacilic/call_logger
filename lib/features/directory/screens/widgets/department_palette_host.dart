import '../../providers/department_directory_provider.dart';

/// Προαιρετικό πλαίσιο φόρμας (τρέχον τμήμα + notifier) για ενημέρωση βάσης.
class DepartmentPaletteHost {
  const DepartmentPaletteHost({
    this.editingDepartmentId,
    this.directoryNotifier,
    this.onEditingDepartmentColorChanged,
  });

  final int? editingDepartmentId;
  final DepartmentDirectoryNotifier? directoryNotifier;

  /// Κλήση όταν αλλάζει το χρώμα του τμήματος που επεξεργάζεται η φόρμα (π.χ. μετά από καθαρισμό).
  final void Function(String hex)? onEditingDepartmentColorChanged;
}
