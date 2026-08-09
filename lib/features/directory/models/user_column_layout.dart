import 'dart:convert';

import 'user_directory_column.dart';

/// Αποτέλεσμα ανάγνωσης ρυθμίσεων στηλών χρηστών (σειρά πλήρους λίστας +
/// ποια κλειδιά είναι ορατά).
typedef UserColumnLayout = ({
  List<UserDirectoryColumn> order,
  Set<String> visible,
});

/// Ανάγνωση της αποθηκευμένης διάταξης στηλών του καταλόγου υπαλλήλων.
///
/// Δύο μορφές γίνονται δεκτές: το σημερινό αντικείμενο `{order, visible}` και
/// η παλιά σκέτη λίστα κλειδιών. Στήλη που δεν υπάρχει στο αποθηκευμένο
/// κείμενο είναι **νέα** — μπαίνει στο τέλος και ορατή, όπως θα εμφανιζόταν σε
/// καθαρή εγκατάσταση· αλλιώς κάθε νέα στήλη θα γεννιόταν κρυφή για όσους
/// έχουν ήδη ρυθμίσει τον πίνακά τους.
UserColumnLayout? parseUserColumnLayoutJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return _parseObjectForm(decoded);
    }
    if (decoded is List) {
      return _parseLegacyListForm(decoded);
    }
  } catch (_) {}
  return null;
}

UserColumnLayout _parseObjectForm(Map<String, dynamic> decoded) {
  final o = decoded['order'];
  final v = decoded['visible'];
  final seenKeys = <String>{};
  final order = <UserDirectoryColumn>[];
  if (o is List) {
    for (final e in o) {
      if (e is! String) continue;
      final c = UserDirectoryColumn.fromKey(e);
      if (c != null && seenKeys.add(c.key)) order.add(c);
    }
  }
  final addedKeys = _appendMissingColumns(order, seenKeys);

  Set<String> visible;
  if (v is List && v.isNotEmpty) {
    visible = {};
    for (final e in v) {
      if (e is String && UserDirectoryColumn.fromKey(e) != null) {
        visible.add(e);
      }
    }
    if (visible.isEmpty) {
      visible = {for (final c in order) c.key};
    } else {
      visible.addAll(addedKeys);
    }
  } else {
    visible = {for (final c in order) c.key};
  }
  return (order: UserDirectoryColumn.pinSelectionFirst(order), visible: visible);
}

UserColumnLayout? _parseLegacyListForm(List<dynamic> decoded) {
  final order = <UserDirectoryColumn>[];
  final seen = <String>{};
  for (final e in decoded) {
    if (e is! String) continue;
    final c = UserDirectoryColumn.fromKey(e);
    if (c != null && seen.add(c.key)) order.add(c);
  }
  if (order.isEmpty) return null;
  final visible = Set<String>.from(seen);
  visible.addAll(_appendMissingColumns(order, seen));
  return (order: UserDirectoryColumn.pinSelectionFirst(order), visible: visible);
}

/// Προσθέτει στο τέλος όσες στήλες λείπουν και επιστρέφει τα κλειδιά τους.
Set<String> _appendMissingColumns(
  List<UserDirectoryColumn> order,
  Set<String> seenKeys,
) {
  final added = <String>{};
  for (final c in UserDirectoryColumn.all) {
    if (!seenKeys.contains(c.key)) {
      order.add(c);
      added.add(c.key);
    }
  }
  return added;
}
