// Οι ρυθμίσεις σώζονται τη στιγμή που αλλάζει ο διακόπτης, χωρίς να τις
// περιμένει η διεπαφή. Με σκέτο `unawaited` όμως η αποτυχία χανόταν σιωπηλά.
//
// Ο κανόνας δεν μπορεί να μείνει σε ένα σχόλιο: η επόμενη ρύθμιση που θα
// προστεθεί θα τον ξεχνούσε, και το λάθος δεν φαίνεται πουθενά — ούτε στο
// analyze, ούτε στην οθόνη. Γι' αυτό υπάρχει αυτός ο φρουρός.
//
//   flutter test test/features/history/lansweeper_settings_writes_are_reported_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Αρχεία που γράφουν ρυθμίσεις Lansweeper από τη διεπαφή.
const _guardedFiles = <String>[
  'lib/features/history/widgets/lansweeper/lansweeper_ticket_submit_settings_section.dart',
  'lib/features/history/widgets/lansweeper/lansweeper_settings_persistence.dart',
];

/// Μοτίβα που δείχνουν εγγραφή ρύθμισης πεταμένη στο κενό.
final _forbidden = RegExp(
  r'unawaited\(\s*(ref\s*\.\s*read|notifier\s*\.\s*set|notifier\s*\.\s*replace)',
);

void main() {
  group('Ρυθμίσεις Lansweeper — καμία εγγραφή δεν αποτυγχάνει σιωπηλά', () {
    for (final path in _guardedFiles) {
      test('$path: καμία εγγραφή ρύθμισης μέσα σε σκέτο unawaited', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'το αρχείο μετακινήθηκε;');

        final offenders = <String>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_forbidden.hasMatch(lines[i])) {
            offenders.add('  γρ. ${i + 1}: ${lines[i].trim()}');
          }
        }

        expect(
          offenders,
          isEmpty,
          reason:
              'Η εγγραφή ρύθμισης περνά από την persistSettingInBackground, '
              'ώστε η αποτυχία να φτάνει στον χρήστη:\n${offenders.join('\n')}',
        );
      });
    }

    test('η ενότητα ρυθμίσεων χρησιμοποιεί όντως τον βοηθό', () {
      final source = File(_guardedFiles.first).readAsStringSync();
      expect(
        source.contains('persistSettingInBackground('),
        isTrue,
        reason: 'αλλιώς ο φρουρός παραπάνω θα ήταν κενός',
      );
    });
  });
}
