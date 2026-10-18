// Unit tests: ανάγνωση της αποθηκευμένης διάταξης στηλών των πινάκων Καταλόγου.
//
//   flutter test test/features/directory/catalog_column_layout_test.dart

import 'dart:convert';

import 'package:call_logger/features/directory/models/catalog_column_layout.dart';
import 'package:call_logger/features/directory/models/category_directory_column.dart';
import 'package:call_logger/features/directory/models/department_directory_column.dart';
import 'package:call_logger/features/directory/models/equipment_column.dart';
import 'package:call_logger/features/directory/models/user_directory_column.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogColumnLayout<UserDirectoryColumn>? _users(String raw) =>
    parseCatalogColumnLayoutJson(
      raw,
      all: UserDirectoryColumn.all,
      defaultVisible: {for (final c in UserDirectoryColumn.all) c.key},
    );

void main() {
  group('Αποθηκευμένη διάταξη στηλών καταλόγου υπαλλήλων', () {
    test('στήλη που δεν υπάρχει στις ρυθμίσεις εμφανίζεται ορατή', () {
      // Διάταξη αποθηκευμένη πριν προστεθεί η στήλη «Εξοπλισμός».
      final raw = jsonEncode({
        'order': ['selection', 'id', 'last_name', 'first_name', 'notes'],
        'visible': ['selection', 'id', 'last_name', 'first_name'],
      });

      final layout = _users(raw);

      expect(layout, isNotNull);
      expect(
        layout!.order.map((c) => c.key),
        contains(UserDirectoryColumn.equipment.key),
      );
      expect(layout.visible, contains(UserDirectoryColumn.equipment.key));
    });

    test('στήλη που ο χρήστης έκρυψε ο ίδιος παραμένει κρυφή', () {
      final raw = jsonEncode({
        'order': [for (final c in UserDirectoryColumn.all) c.key],
        'visible': [
          for (final c in UserDirectoryColumn.all)
            if (c.key != UserDirectoryColumn.notes.key) c.key,
        ],
      });

      final layout = _users(raw);

      expect(layout, isNotNull);
      expect(layout!.visible, isNot(contains(UserDirectoryColumn.notes.key)));
    });

    test('η παλιά μορφή σκέτης λίστας δέχεται κι αυτή τις νέες στήλες', () {
      final raw = jsonEncode(['id', 'last_name', 'phone']);

      final layout = _users(raw);

      expect(layout, isNotNull);
      expect(layout!.visible, contains(UserDirectoryColumn.equipment.key));
      expect(layout.visible, contains('phone'));
    });

    test('η στήλη επιλογής μένει πάντα πρώτη', () {
      final raw = jsonEncode({
        'order': ['notes', 'selection', 'id'],
        'visible': ['notes', 'selection', 'id'],
      });

      final layout = _users(raw);

      expect(layout!.order.first.key, UserDirectoryColumn.selection.key);
    });

    test('χαλασμένο κείμενο ρυθμίσεων δεν ρίχνει τη φόρτωση', () {
      expect(_users('{όχι json'), isNull);
      expect(_users('[]'), isNull);
    });
  });

  // Ο κανόνας των Υπαλλήλων ισχύει πια και στους άλλους τρεις πίνακες: νέα
  // στήλη παίρνει την ορατότητα που θα είχε σε καθαρή εγκατάσταση.
  group('Ο ίδιος κανόνας στους άλλους πίνακες', () {
    test('Τμήματα: νέα στήλη εμφανίζεται ορατή', () {
      // Διάταξη αποθηκευμένη πριν υπάρξει η στήλη «Χρώμα».
      final raw = jsonEncode({
        'order': ['selection', 'id', 'name'],
        'visible': ['selection', 'name'],
      });

      final layout = parseCatalogColumnLayoutJson(
        raw,
        all: DepartmentDirectoryColumn.all,
        defaultVisible: {for (final c in DepartmentDirectoryColumn.all) c.key},
      );

      expect(layout!.visible, contains(DepartmentDirectoryColumn.color.key));
      expect(
        layout.visible,
        isNot(contains(DepartmentDirectoryColumn.id.key)),
        reason: 'Ό,τι έκρυψε ο χρήστης μένει κρυφό',
      );
    });

    test('Εξοπλισμός: νέα στήλη κρυφή από προεπιλογή μένει κρυφή', () {
      // Διάταξη αποθηκευμένη πριν υπάρξει η στήλη «Τμήμα», που είναι κρυφή
      // και σε καθαρή εγκατάσταση.
      final raw = jsonEncode({
        'order': ['selection', 'code'],
        'visible': ['selection', 'code'],
      });

      final layout = parseCatalogColumnLayoutJson(
        raw,
        all: EquipmentColumn.all,
        defaultVisible: {for (final c in EquipmentColumn.defaults) c.key},
      );

      expect(
        layout!.order.map((c) => c.key),
        contains(EquipmentColumn.department.key),
      );
      expect(layout.visible, isNot(contains(EquipmentColumn.department.key)));
    });

    test('Κατηγορίες: χωρίς ορατές στήλες γυρίζει στην προεπιλογή', () {
      final raw = jsonEncode({
        'order': ['name', 'selection'],
        'visible': <String>[],
      });

      final layout = parseCatalogColumnLayoutJson(
        raw,
        all: CategoryDirectoryColumn.all,
        defaultVisible: {
          CategoryDirectoryColumn.selection.key,
          CategoryDirectoryColumn.name.key,
        },
      );

      expect(layout!.visible, {
        CategoryDirectoryColumn.selection.key,
        CategoryDirectoryColumn.name.key,
      });
      expect(layout.order.first.key, CategoryDirectoryColumn.selection.key);
    });
  });
}
