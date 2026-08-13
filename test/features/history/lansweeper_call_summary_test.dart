// Πού ανήκει κάθε πληροφορία της αναφοράς: στην κεφαλίδα της ομάδας ή στην
// κάρτα της κλήσης. Ο κανόνας — «στο ψηλότερο σημείο όπου είναι αληθής» —
// είναι λογική, όχι εμφάνιση, και ελέγχεται εδώ.
//
//   flutter test test/features/history/lansweeper_call_summary_test.dart

import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_call_summary.dart';
import 'package:flutter_test/flutter_test.dart';

CallModel _call({
  String? callerText,
  String? phoneText,
  String? departmentText,
  String? equipmentText,
  String? category,
  String? date,
  String? time,
}) {
  return CallModel(
    callerText: callerText,
    phoneText: phoneText,
    departmentText: departmentText,
    equipmentText: equipmentText,
    category: category,
    date: date,
    time: time,
  );
}

void main() {
  group('κοινή τιμή ομάδας', () {
    test('ίδια τιμή παντού ανεβαίνει στην κεφαλίδα', () {
      final calls = [
        _call(phoneText: '3801'),
        _call(phoneText: '3801'),
        _call(phoneText: '3801'),
      ];

      expect(
        LansweeperCallSummary.sharedValue(calls, (c) => c.phoneText),
        '3801',
      );
    });

    // Η ομάδα «Άγνωστος» μαζεύει κλήσεις άσχετων ανθρώπων: μια τιμή που ισχύει
    // για τη μία δεν επιτρέπεται να παρουσιαστεί ως τιμή όλης της ομάδας.
    test('διαφορετικές τιμές δεν ανεβαίνουν', () {
      final calls = [
        _call(departmentText: 'Παθολογική'),
        _call(departmentText: 'Γραφείο Προμηθειών'),
      ];

      expect(
        LansweeperCallSummary.sharedValue(calls, (c) => c.departmentText),
        isNull,
      );
    });

    test('έστω μία κενή τιμή ακυρώνει την ανάβαση', () {
      final calls = [_call(phoneText: '3801'), _call(phoneText: '')];

      expect(
        LansweeperCallSummary.sharedValue(calls, (c) => c.phoneText),
        isNull,
      );
    });

    test('τα κενά γύρω από την τιμή δεν τη διαφοροποιούν', () {
      final calls = [_call(phoneText: ' 3801 '), _call(phoneText: '3801')];

      expect(
        LansweeperCallSummary.sharedValue(calls, (c) => c.phoneText),
        '3801',
      );
    });

    test('μία μόνο κλήση δίνει τη δική της τιμή', () {
      expect(
        LansweeperCallSummary.sharedValue([
          _call(departmentText: 'Παθολογική'),
        ], (c) => c.departmentText),
        'Παθολογική',
      );
    });

    test('κενή ομάδα δεν δίνει τιμή', () {
      expect(
        LansweeperCallSummary.sharedValue(
          const <CallModel>[],
          (c) => c.phoneText,
        ),
        isNull,
      );
    });
  });

  group('υπόδειξη χρονοσφραγίδας', () {
    test('κρατά και τα τέσσερα στοιχεία μαζί με πλήρη ημερομηνία', () {
      final tooltip = LansweeperCallSummary.callTooltip(
        _call(
          callerText: 'Μαρία Παπαδοπούλου',
          phoneText: '3801',
          departmentText: 'Γραφείο Προμηθειών',
          equipmentText: 'PC3257',
          date: '2026-07-22',
          time: '14:52',
        ),
      );

      expect(tooltip, contains('22/07/2026 14:52'));
      expect(tooltip, contains('Καλών: Μαρία Παπαδοπούλου'));
      expect(tooltip, contains('Τηλέφωνο: 3801'));
      expect(tooltip, contains('Τμήμα: Γραφείο Προμηθειών'));
      expect(tooltip, contains('Εξοπλισμός: PC3257'));
    });

    test('τα πεδία που λείπουν δεν αφήνουν άδειες γραμμές', () {
      final tooltip = LansweeperCallSummary.callTooltip(
        _call(equipmentText: 'PC3257', date: '2026-07-22', time: '14:52'),
      );

      expect(tooltip, contains('Εξοπλισμός: PC3257'));
      expect(tooltip, isNot(contains('Τηλέφωνο')));
      expect(tooltip, isNot(contains('Τμήμα')));
      expect(tooltip.split('\n'), hasLength(2));
    });
  });

  group('ετικέτα ημερομηνίας', () {
    test('η σύντομη μορφή αφήνει έξω το έτος', () {
      final call = _call(date: '2026-07-22', time: '14:52');

      expect(LansweeperCallSummary.shortDateLabel(call), '22/07 14:52');
      expect(LansweeperCallSummary.fullDateLabel(call), '22/07/2026 14:52');
    });

    test('κλήση χωρίς έγκυρη ημερομηνία δεν ρίχνει τη λίστα', () {
      expect(
        () => LansweeperCallSummary.shortDateLabel(_call(date: 'σκουπίδι')),
        returnsNormally,
      );
    });
  });
}
