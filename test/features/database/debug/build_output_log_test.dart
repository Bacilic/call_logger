// Συσσωρευτής γραμμών εξόδου μεταγλώττισης.
//
// Συμβόλαιο: η προσάρτηση δεν ξαναγράφει ό,τι έχει ήδη γραφτεί.
//
//   flutter test test/features/database/debug/build_output_log_test.dart

import 'package:call_logger/features/database/debug/build_output_log.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  test('οι γραμμές κρατούν τη σειρά τους και μετριούνται', () {
    final log = BuildOutputLog();
    expect(log.isEmpty, isTrue);

    log.append('πρώτη');
    log.append('δεύτερη');

    expect(log.length, 2);
    expect(log.lines, ['πρώτη', 'δεύτερη']);
    expect(log.toText(), 'πρώτη\nδεύτερη');
  });

  test('κάθε προσθήκη ειδοποιεί μία φορά', () {
    final log = BuildOutputLog();
    var notifications = 0;
    log.addListener(() => notifications++);

    log.append('α');
    log.append('β');

    expect(notifications, 2);
  });

  test('ο καθαρισμός αδειάζει και ειδοποιεί μόνο όταν υπάρχει κάτι', () {
    final log = BuildOutputLog();
    var notifications = 0;
    log.addListener(() => notifications++);

    log.clear();
    expect(
      notifications,
      0,
      reason: greekExpectMsg(
        'Καθαρισμός άδειου log δεν είναι αλλαγή — δεν ξαναχτίζει την οθόνη',
      ),
    );

    log.append('α');
    log.clear();

    expect(log.isEmpty, isTrue);
    expect(notifications, 2);
  });

  test('η άποψη γραμμών δεν επιτρέπει αλλοίωση από τον καταναλωτή', () {
    final log = BuildOutputLog();
    log.append('α');

    expect(
      () => log.lines.add('παρείσακτη'),
      throwsUnsupportedError,
      reason: greekExpectMsg(
        'Ο κάτοχος του log είναι ένας· η προβολή διαβάζει, δεν γράφει',
      ),
    );
  });
}
