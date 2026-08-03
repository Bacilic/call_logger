// Ενιαία εμφάνιση διάρκειας κλήσης — καθαρή συνάρτηση, χωρίς διεπαφή.
//
//   flutter test test/core/utils/call_duration_format_test.dart

import 'package:call_logger/core/utils/call_duration_format.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  group('formatCallDurationSeconds — κάτω από την ώρα: λλ:δδ', () {
    test('μηδέν', () {
      expect(formatCallDurationSeconds(0), '00:00');
    });

    test('μόνο δευτερόλεπτα', () {
      expect(formatCallDurationSeconds(45), '00:45');
    });

    test('πραγματική κλήση 191 δευτερολέπτων', () {
      expect(formatCallDurationSeconds(191), '03:11');
    });

    test('609 δευτερόλεπτα → 10:09, όχι δεκαδικά λεπτά', () {
      expect(
        formatCallDurationSeconds(609),
        '10:09',
        reason: greekExpectMsg(
          'Τα 609 δευτερόλεπτα είναι 10 λεπτά και 9 δευτερόλεπτα — '
          'ποτέ «10,15»',
        ),
      );
    });

    test('ένα δευτερόλεπτο πριν την ώρα', () {
      expect(formatCallDurationSeconds(3599), '59:59');
    });
  });

  group('formatCallDurationSeconds — από την ώρα και πάνω: ωω:λλ:δδ', () {
    test('ακριβώς μία ώρα', () {
      expect(formatCallDurationSeconds(3600), '01:00:00');
    });

    test('δύο ώρες δεν εμφανίζονται ως 120 λεπτά', () {
      expect(
        formatCallDurationSeconds(7200),
        '02:00:00',
        reason: greekExpectMsg(
          'Το «120:00» διαβάζεται ως δύο λεπτά — οι ώρες θέλουν δικό τους πεδίο',
        ),
      );
    });

    test('ώρες, λεπτά και δευτερόλεπτα μαζί', () {
      expect(formatCallDurationSeconds(3661), '01:01:01');
    });

    test('πάνω από 24 ώρες δεν μηδενίζεται', () {
      expect(
        formatCallDurationSeconds(90000),
        '25:00:00',
        reason: greekExpectMsg(
          'Χωρίς ταβάνι 24 ωρών: οι 25 ώρες δεν γίνονται «01:00:00»',
        ),
      );
    });
  });

  group('formatCallDurationSeconds — ακατέργαστες και άκυρες τιμές', () {
    test('τιμή βάσης ως κείμενο', () {
      expect(formatCallDurationSeconds('191'), '03:11');
    });

    test('δεκαδικά δευτερόλεπτα στρογγυλοποιούνται', () {
      expect(formatCallDurationSeconds(190.6), '03:11');
    });

    test('απούσα τιμή', () {
      expect(formatCallDurationSeconds(null), '—');
    });

    test('κενό ή άκυρο κείμενο', () {
      expect(formatCallDurationSeconds(''), '—');
      expect(formatCallDurationSeconds('άγνωστο'), '—');
    });

    test('NaN', () {
      expect(
        formatCallDurationSeconds(double.nan),
        '—',
        reason: greekExpectMsg(
          'Άκυρος υπολογισμός δεν πρέπει να περνά για μετρημένο μηδέν',
        ),
      );
    });

    test('αρνητική τιμή δεν παράγει αρνητική ώρα', () {
      expect(formatCallDurationSeconds(-5), '00:00');
    });

    test('η ένδειξη απουσίας παραμετροποιείται', () {
      expect(formatCallDurationSeconds(null, ifMissing: '00:00'), '00:00');
    });
  });

  group('formatAggregateDurationSeconds — σύνολα με ρητές μονάδες', () {
    test('ώρες και λεπτά — τα δευτερόλεπτα δεν προσθέτουν τίποτα', () {
      expect(formatAggregateDurationSeconds(108900), '30ω:15λ');
    });

    test('κάτω από την ώρα — λεπτά και δευτερόλεπτα', () {
      expect(formatAggregateDurationSeconds(2730), '45λ:30δ');
    });

    test('κάτω από το λεπτό — μόνο δευτερόλεπτα', () {
      expect(
        formatAggregateDurationSeconds(45),
        '45δ',
        reason: greekExpectMsg(
          'Το «00:00:45» είναι φλύαρο για σαρανταπέντε δευτερόλεπτα',
        ),
      );
    });

    test('η μονάδα ξεχωρίζει ώρες από λεπτά στην ίδια γραφή', () {
      expect(formatAggregateDurationSeconds(1815), '30λ:15δ');
      expect(formatAggregateDurationSeconds(109800), '30ω:30λ');
    });

    test('ακριβώς μία ώρα', () {
      expect(formatAggregateDurationSeconds(3600), '1ω:00λ');
    });

    test('μηδέν και αρνητικά', () {
      expect(formatAggregateDurationSeconds(0), '0δ');
      expect(formatAggregateDurationSeconds(-5), '0δ');
    });

    test('άκυρη τιμή', () {
      expect(formatAggregateDurationSeconds(double.nan), '—');
      expect(formatAggregateDurationSeconds(null, ifMissing: '0δ'), '0δ');
    });
  });

  group('callDurationFieldLabel — λεζάντα του πεδίου επεξεργασίας', () {
    test('δείχνει τον πραγματικό χρόνο δίπλα στα δευτερόλεπτα', () {
      expect(
        callDurationFieldLabel('68'),
        'Διάρκεια (δτρλ) - 01:08',
        reason: greekExpectMsg(
          'Το πεδίο κρατά δευτερόλεπτα· η λεζάντα λέει τι σημαίνουν',
        ),
      );
    });

    test('κλήση πάνω από την ώρα', () {
      expect(callDurationFieldLabel('7200'), 'Διάρκεια (δτρλ) - 02:00:00');
    });

    test('κενό πεδίο — σκέτη λεζάντα', () {
      expect(callDurationFieldLabel(''), 'Διάρκεια (δτρλ)');
    });

    test('άκυρη πληκτρολόγηση δεν δείχνει παραπλανητικό χρόνο', () {
      expect(callDurationFieldLabel('abc'), 'Διάρκεια (δτρλ)');
    });
  });
}
