import 'category_model.dart';

/// Ορισμός στήλης πίνακα κατηγοριών (κατάλογος).
class CategoryDirectoryColumn {
  const CategoryDirectoryColumn._(this.key, this.label, this.sortKey);

  final String key;
  final String label;
  final String? sortKey;

  static const selection =
      CategoryDirectoryColumn._('selection', 'Επιλογή', null);
  static const id = CategoryDirectoryColumn._('id', 'ID', 'id');
  static const name = CategoryDirectoryColumn._('name', 'Όνομα', 'name');

  static const List<CategoryDirectoryColumn> all = [
    selection,
    id,
    name,
  ];

  static CategoryDirectoryColumn? fromKey(String k) {
    for (final c in all) {
      if (c.key == k) return c;
    }
    return null;
  }

  static List<CategoryDirectoryColumn> pinSelectionFirst(
    List<CategoryDirectoryColumn> order,
  ) {
    if (!order.contains(selection)) {
      return List<CategoryDirectoryColumn>.from(order);
    }
    return [
      selection,
      ...order.where((c) => c != selection),
    ];
  }

  String get editFocusField => 'name';

  String searchText(CategoryModel c) {
    switch (key) {
      case 'selection':
        return '';
      case 'id':
        return '${c.id ?? ''}';
      case 'name':
        return c.name;
      default:
        return '';
    }
  }
}
