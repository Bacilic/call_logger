// Unit test: ο controller ορθογραφίας δεν ξαναπρογραμματίζει τον εαυτό του.
//
// Ο έλεγχος ορθογραφίας τελειώνει με notifyListeners(), και ο ίδιος ο
// controller είναι ακροατής του εαυτού του — χωρίς φρουρό, κάθε ανοιχτό πεδίο
// κειμένου ξαναϋπολόγιζε ορθογραφία κάθε 500ms για πάντα.
//
//   flutter test test/core/widgets/spell_check_controller_test.dart

import 'package:call_logger/core/widgets/spell_check_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpellCheckController — προγραμματισμός ανάλυσης', () {
    late SpellCheckController controller;

    setUp(() {
      controller = SpellCheckController(spellCheckEnabled: false);
    });

    tearDown(() {
      controller.dispose();
    });

    test('η ανάλυση δεν ξαναπρογραμματίζει τον εαυτό της', () {
      fakeAsync((async) {
        controller.text = 'Ο εκτυπωτής βγάζει κενές σελίδες.';

        // Μετά το debounce η ανάλυση τρέχει μία φορά…
        async.elapse(const Duration(milliseconds: 600));
        expect(async.pendingTimers, isEmpty);

        // …και δεν αφήνει ουρά που ξαναγεννιέται μόνη της.
        async.elapse(const Duration(seconds: 5));
        expect(
          async.pendingTimers,
          isEmpty,
          reason: 'Χωρίς πληκτρολόγηση δεν πρέπει να μένει κανένας διακόπτης',
        );
      });
    });

    test('νέα πληκτρολόγηση προγραμματίζει κανονικά νέα ανάλυση', () {
      fakeAsync((async) {
        controller.text = 'πρώτο';
        expect(async.pendingTimers, hasLength(1));
        async.elapse(const Duration(milliseconds: 600));
        expect(async.pendingTimers, isEmpty);

        controller.text = 'δεύτερο';
        expect(
          async.pendingTimers,
          hasLength(1),
          reason: 'Αλλαγή κειμένου = νέα ανάλυση',
        );
        async.elapse(const Duration(milliseconds: 600));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('αλλαγή μόνο της επιλογής δεν ζητά νέα ανάλυση', () {
      fakeAsync((async) {
        controller.text = 'Ο εκτυπωτής';
        async.elapse(const Duration(milliseconds: 600));
        expect(async.pendingTimers, isEmpty);

        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 2,
        );

        expect(
          async.pendingTimers,
          isEmpty,
          reason: 'Το κείμενο δεν άλλαξε — η ανάλυση ισχύει ακόμα',
        );
      });
    });
  });
}
