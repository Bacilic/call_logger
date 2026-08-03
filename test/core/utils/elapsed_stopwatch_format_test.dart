// Χρονόμετρο εργασίας με χιλιοστά και δυναμικά ψηφία.
//
// Η ακολουθία που ζήτησε ο χρήστης είναι η προδιαγραφή:
//   :1 → :999 → 1:001 → 59:999 → 1:01:652 → 23:46:732
//
//   flutter test test/core/utils/elapsed_stopwatch_format_test.dart

import 'package:call_logger/core/utils/elapsed_stopwatch_format.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  test('κάτω από ένα δευτερόλεπτο: μόνο χιλιοστά, χωρίς μηδενικά μπροστά', () {
    expect(formatElapsedWithMillis(const Duration(milliseconds: 1)), ':1');
    expect(formatElapsedWithMillis(const Duration(milliseconds: 999)), ':999');
    expect(
      formatElapsedWithMillis(Duration.zero),
      ':0',
      reason: greekExpectMsg('Η αφετηρία δείχνει μηδέν, όχι κενό'),
    );
  });

  test('από ένα δευτερόλεπτο: δευτερόλεπτα χωρίς padding, χιλιοστά με 3 ψηφία', () {
    expect(formatElapsedWithMillis(const Duration(milliseconds: 1001)), '1:001');
    expect(
      formatElapsedWithMillis(const Duration(milliseconds: 59999)),
      '59:999',
    );
  });

  test('από ένα λεπτό: προστίθεται η μονάδα λεπτών χωρίς padding', () {
    expect(
      formatElapsedWithMillis(
        const Duration(minutes: 1, seconds: 1, milliseconds: 652),
      ),
      '1:01:652',
    );
    expect(
      formatElapsedWithMillis(
        const Duration(minutes: 23, seconds: 46, milliseconds: 732),
      ),
      '23:46:732',
    );
  });

  test('από μία ώρα: προστίθεται η μονάδα ωρών', () {
    expect(formatElapsedWithMillis(const Duration(hours: 1)), '1:00:00:000');
    expect(
      formatElapsedWithMillis(
        const Duration(hours: 2, minutes: 5, seconds: 9, milliseconds: 40),
      ),
      '2:05:09:040',
    );
  });

  test('αρνητική διάρκεια δεν παράγει σκουπίδια', () {
    expect(
      formatElapsedWithMillis(const Duration(milliseconds: -5)),
      ':0',
      reason: greekExpectMsg(
        'Ρολόι που γύρισε πίσω δεν πρέπει να δείχνει αρνητικό χρόνο',
      ),
    );
  });
}
