import '../../calls/models/user_model.dart';

/// Ορισμός στήλης πίνακα χρηστών (κατάλογος): κλειδί, ετικέτα, ταξινόμηση.
class UserDirectoryColumn {
  const UserDirectoryColumn._(this.key, this.label, this.sortKey);

  final String key;
  final String label;
  final String? sortKey;

  static const selection = UserDirectoryColumn._('selection', 'Επιλογή', null);
  static const id = UserDirectoryColumn._('id', 'ID', 'id');
  static const lastName =
      UserDirectoryColumn._('last_name', 'Επώνυμο', 'last_name');
  static const firstName =
      UserDirectoryColumn._('first_name', 'Όνομα', 'first_name');
  static const phone = UserDirectoryColumn._('phone', 'Τηλέφωνο', 'phone');
  static const department =
      UserDirectoryColumn._('department', 'Τμήμα', 'department');
  static const notes = UserDirectoryColumn._('notes', 'Σημειώσεις', 'notes');

  /// Προεπιλογή: όλες οι στήλες ορατές.
  static const List<UserDirectoryColumn> defaults = [
    selection,
    id,
    lastName,
    firstName,
    phone,
    department,
    notes,
  ];

  static const List<UserDirectoryColumn> all = [
    selection,
    id,
    lastName,
    firstName,
    phone,
    department,
    notes,
  ];

  static UserDirectoryColumn? fromKey(String k) {
    for (final c in all) {
      if (c.key == k) return c;
    }
    return null;
  }

  /// Η στήλη [selection] πάντα στην πρώτη θέση της πλήρους σειράς (αν υπάρχει στη λίστα).
  static List<UserDirectoryColumn> pinSelectionFirst(
    List<UserDirectoryColumn> order,
  ) {
    if (!order.contains(selection)) {
      return List<UserDirectoryColumn>.from(order);
    }
    return [
      selection,
      ...order.where((c) => c != selection),
    ];
  }

  /// Πεδίο εστίασης στη φόρμα επεξεργασίας μετά από διπλό κλικ.
  String get editFocusField {
    switch (key) {
      case 'selection':
      case 'id':
        return 'id';
      case 'last_name':
        return 'lastName';
      case 'first_name':
        return 'firstName';
      case 'phone':
        return 'phone';
      case 'department':
        return 'department';
      case 'notes':
        return 'notes';
      default:
        return 'firstName';
    }
  }

  /// Κείμενο για αναζήτηση (οι στήλες χωρίς κείμενο παραλείπονται).
  String searchText(UserModel u) {
    switch (key) {
      case 'selection':
        return '';
      case 'id':
        return '${u.id ?? ''}';
      case 'last_name':
        return u.lastName ?? '';
      case 'first_name':
        return u.firstName ?? '';
      case 'phone':
        return u.phoneJoined;
      case 'department':
        return u.departmentName ?? '';
      case 'notes':
        return u.notes ?? '';
      default:
        return '';
    }
  }
}
