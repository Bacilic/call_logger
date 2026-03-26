import 'department_model.dart';

/// Ορισμός στήλης πίνακα τμημάτων (κατάλογος): κλειδί, ετικέτα, ταξινόμηση.
class DepartmentDirectoryColumn {
  const DepartmentDirectoryColumn._(this.key, this.label, this.sortKey);

  final String key;
  final String label;
  final String? sortKey;

  static const selection =
      DepartmentDirectoryColumn._('selection', 'Επιλογή', null);
  static const id = DepartmentDirectoryColumn._('id', 'ID', 'id');
  static const name = DepartmentDirectoryColumn._('name', 'Όνομα', 'name');
  static const building =
      DepartmentDirectoryColumn._('building', 'Κτίριο', 'building');
  static const color =
      DepartmentDirectoryColumn._('color', 'Χρώμα', 'color');
  static const phones =
      DepartmentDirectoryColumn._('phones', 'Τηλέφωνα', 'phones');
  static const equipment =
      DepartmentDirectoryColumn._('equipment', 'Εξοπλισμός', 'equipment');
  static const notes =
      DepartmentDirectoryColumn._('notes', 'Σημειώσεις', 'notes');

  static const List<DepartmentDirectoryColumn> all = [
    selection,
    id,
    name,
    building,
    color,
    phones,
    equipment,
    notes,
  ];

  static DepartmentDirectoryColumn? fromKey(String k) {
    for (final c in all) {
      if (c.key == k) return c;
    }
    return null;
  }

  static List<DepartmentDirectoryColumn> pinSelectionFirst(
    List<DepartmentDirectoryColumn> order,
  ) {
    if (!order.contains(selection)) {
      return List<DepartmentDirectoryColumn>.from(order);
    }
    return [
      selection,
      ...order.where((c) => c != selection),
    ];
  }

  String get editFocusField {
    switch (key) {
      case 'selection':
      case 'id':
        return 'name';
      case 'name':
        return 'name';
      case 'building':
        return 'building';
      case 'color':
        return 'color';
      case 'phones':
        return 'phones';
      case 'equipment':
        return 'equipment';
      case 'notes':
        return 'notes';
      default:
        return 'name';
    }
  }

  String searchText(DepartmentModel d) {
    switch (key) {
      case 'selection':
        return '';
      case 'id':
        return '${d.id ?? ''}';
      case 'name':
        return d.name;
      case 'building':
        return d.building ?? '';
      case 'color':
        return d.color ?? '';
      case 'notes':
        return d.notes ?? '';
      case 'phones':
      case 'equipment':
        return '';
      default:
        return '';
    }
  }
}
