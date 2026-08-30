// Κάθε αρχείο JSON που γράφει η εφαρμογή τελειώνει με νέα γραμμή.
//
// Το σφάλμα που φυλάει: η «Δημοσίευση έκδοσης» έγραφε το changelog χωρίς
// τελική νέα γραμμή, οπότε το git σήμαινε την τελευταία γραμμή ως αλλαγμένη
// σε κάθε επόμενη δημοσίευση — θόρυβος που έκρυβε τις πραγματικές αλλαγές.
//
//   flutter test test/core/utils/json_document_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/utils/json_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encodeJsonDocument', () {
    test('κλείνει πάντα με νέα γραμμή', () {
      expect(encodeJsonDocument({'a': 1}), endsWith('\n'));
      expect(encodeJsonDocument(<Object>[]), endsWith('\n'));
      expect(encodeJsonDocument(const <String, Object>{}), endsWith('\n'));
    });

    test('μία νέα γραμμή, όχι δύο', () {
      final text = encodeJsonDocument({'a': 1});
      expect(text.endsWith('\n\n'), isFalse);
    });

    test('το περιεχόμενο μένει έγκυρο JSON με στοίχιση δύο κενών', () {
      final text = encodeJsonDocument({
        'version': 'Unreleased',
        'added': ['πρώτο'],
      });

      expect(jsonDecode(text), {
        'version': 'Unreleased',
        'added': ['πρώτο'],
      });
      expect(text, contains('\n  "version": "Unreleased"'));
    });
  });

  group('Το αρχείο του έργου', () {
    test('το assets/changelog.json τελειώνει με νέα γραμμή', () {
      final file = File('assets/changelog.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Το τεστ τρέχει από τη ρίζα του έργου.',
      );

      expect(
        file.readAsStringSync().endsWith('\n'),
        isTrue,
        reason:
            'Χωρίς αυτήν, κάθε δημοσίευση εμφανίζει την τελευταία γραμμή ως '
            'αλλαγμένη χωρίς λόγο στη σύγκριση εκδόσεων.',
      );
    });
  });
}
