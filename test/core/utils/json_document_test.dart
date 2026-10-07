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

  group('findDuplicateJsonKeys', () {
    test('βρίσκει το δεύτερο κλειδί στην ίδια κάρτα, με τη γραμμή του', () {
      const text =
          '[\n'
          '  {\n'
          '    "version": "Unreleased",\n'
          '    "fixed": ["α"],\n'
          '    "fixed": ["β"]\n'
          '  }\n'
          ']\n';

      expect(findDuplicateJsonKeys(text), [(key: 'fixed', line: 5)]);
    });

    test('το ίδιο κλειδί σε διαφορετικές κάρτες ΔΕΝ είναι διπλό', () {
      const text =
          '[{"version": "Unreleased", "fixed": []},'
          ' {"version": "0.61.0", "fixed": []}]';

      expect(findDuplicateJsonKeys(text), isEmpty);
    });

    test('κείμενο εγγραφής που μοιάζει με κλειδί δεν μετρά', () {
      const text =
          '{"fixed": ["\\"fixed\\": μια εγγραφή, με κόμμα"],'
          ' "added": ["fixed"]}';

      expect(findDuplicateJsonKeys(text), isEmpty);
    });
  });

  group('Το αρχείο του έργου', () {
    test('το assets/changelog.json δεν έχει διπλά κλειδιά', () {
      final text = File('assets/changelog.json').readAsStringSync();

      expect(
        findDuplicateJsonKeys(text),
        isEmpty,
        reason:
            'Διπλό κλειδί σβήνει σιωπηλά τις εγγραφές του πρώτου — π.χ. '
            'εγγραφή σε κάρτα που μόλις σφραγίστηκε.',
      );
    });

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
