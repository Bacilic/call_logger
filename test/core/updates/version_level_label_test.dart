// Ο αριθμός επιπέδου που δείχνει το παράσημο αναβάθμισης.
//
//   flutter test test/core/updates/version_level_label_test.dart

import 'package:call_logger/core/updates/version_level_label.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  group('versionLevelLabel', () {
    test('όσο το major είναι μηδέν, επίπεδο είναι το minor', () {
      expect(versionLevelLabel('0.34.0'), '34');
      expect(versionLevelLabel('0.9.0'), '9');
      expect(versionLevelLabel('0.100.0'), '100');
    });

    test('το patch δεν ανεβάζει επίπεδο', () {
      expect(
        versionLevelLabel('0.34.7'),
        '34',
        reason: greekExpectMsg(
          'Το patch είναι διόρθωση της ίδιας δουλειάς — δεν είναι νέο επίπεδο',
        ),
      );
    });

    test('με major ≥ 1 το επίπεδο γίνεται major.minor ώστε να μην πέφτει', () {
      expect(
        versionLevelLabel('1.0.0'),
        '1.0',
        reason: greekExpectMsg(
          'Σκέτο το minor θα έδειχνε «0» αμέσως μετά το «41» — υποβάθμιση',
        ),
      );
      expect(versionLevelLabel('1.4.2'), '1.4');
      expect(versionLevelLabel('2.11.0'), '2.11');
    });

    test('ό,τι δεν αναγνωρίζεται επιστρέφεται αυτούσιο', () {
      expect(versionLevelLabel('χαλασμένο'), 'χαλασμένο');
      expect(versionLevelLabel(''), '');
      expect(versionLevelLabel('  0.5.0  '), '5');
    });
  });

  group('versionLevelFontSize', () {
    test('μεγαλώνοντας ο αριθμός, μικραίνουν τα γράμματα', () {
      final small = versionLevelFontSize('9');
      final medium = versionLevelFontSize('34');
      final long = versionLevelFontSize('100');
      final longer = versionLevelFontSize('1.12');

      expect(small, medium, reason: greekExpectMsg('1-2 ψηφία: ίδιο μέγεθος'));
      expect(
        long,
        lessThan(medium),
        reason: greekExpectMsg(
          'Χωρίς σμίκρυνση, ο τριψήφιος αριθμός ξεχειλίζει από το εξάγωνο',
        ),
      );
      expect(longer, lessThan(long));
    });
  });
}
