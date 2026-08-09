import 'dart:convert';

import 'package:call_logger/features/directory/models/user_column_layout.dart';
import 'package:call_logger/features/directory/models/user_directory_column.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Αποθηκευμένη διάταξη στηλών καταλόγου υπαλλήλων', () {
    test('στήλη που δεν υπάρχει στις ρυθμίσεις εμφανίζεται ορατή', () {
      // Διάταξη αποθηκευμένη πριν προστεθεί η στήλη «Εξοπλισμός».
      final raw = jsonEncode({
        'order': ['selection', 'id', 'last_name', 'first_name', 'notes'],
        'visible': ['selection', 'id', 'last_name', 'first_name'],
      });

      final layout = parseUserColumnLayoutJson(raw);

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

      final layout = parseUserColumnLayoutJson(raw);

      expect(layout, isNotNull);
      expect(
        layout!.visible,
        isNot(contains(UserDirectoryColumn.notes.key)),
      );
    });

    test('η παλιά μορφή σκέτης λίστας δέχεται κι αυτή τις νέες στήλες', () {
      final raw = jsonEncode(['id', 'last_name', 'phone']);

      final layout = parseUserColumnLayoutJson(raw);

      expect(layout, isNotNull);
      expect(layout!.visible, contains(UserDirectoryColumn.equipment.key));
      expect(layout.visible, contains('phone'));
    });

    test('η στήλη επιλογής μένει πάντα πρώτη', () {
      final raw = jsonEncode({
        'order': ['notes', 'selection', 'id'],
        'visible': ['notes', 'selection', 'id'],
      });

      final layout = parseUserColumnLayoutJson(raw);

      expect(layout!.order.first.key, UserDirectoryColumn.selection.key);
    });

    test('χαλασμένο κείμενο ρυθμίσεων δεν ρίχνει τη φόρτωση', () {
      expect(parseUserColumnLayoutJson('{όχι json'), isNull);
      expect(parseUserColumnLayoutJson('[]'), isNull);
    });
  });
}
