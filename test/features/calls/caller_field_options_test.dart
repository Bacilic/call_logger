// Οι λίστες του πεδίου Καλούντα: μία συνάρτηση ανά λίστα, κοινή για ό,τι
// ζωγραφίζεται και για ό,τι διαλέγουν τα βελάκια και το Enter.
//
//   flutter test test/features/calls/caller_field_options_test.dart

import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/utils/caller_field_options.dart';
import 'package:flutter_test/flutter_test.dart';

UserModel _user(int id, String first, String last, {String? department}) =>
    UserModel(
      id: id,
      firstName: first,
      lastName: last,
      departmentName: department,
    );

void main() {
  final maria = _user(1, 'Μαρία', 'Ψαρρά', department: 'Μικροβιολογικό');
  final nikos = _user(2, 'Νίκος', 'Παππάς', department: 'Ακτινολογικό');

  group('callerOverlayRows', () {
    test('σειρά: υποψήφιοι, μετά ο επιλεγμένος, τελευταίος ο Άγνωστος', () {
      final rows = callerOverlayRows(
        selectedCaller: maria,
        candidates: [maria, nikos],
        showUnknownOption: true,
      );

      expect(rows.map((r) => r.kind).toList(), [
        CallerOverlayRowKind.candidate,
        CallerOverlayRowKind.selected,
        CallerOverlayRowKind.unknown,
      ]);
      expect(rows.map((r) => r.label).toList(), [
        'Νίκος Παππάς (Ακτινολογικό)',
        'Μαρία Ψαρρά',
        kCallerUnknownOption,
      ]);
      expect(
        rows.first.user?.id,
        2,
        reason: 'Ο επιλεγμένος δεν εμφανίζεται δεύτερη φορά ως υποψήφιος',
      );
    });

    test('ο Άγνωστος μόνο όταν το ζητά ο καλών (άδειο πεδίο)', () {
      final rows = callerOverlayRows(
        selectedCaller: null,
        candidates: [maria, nikos],
        showUnknownOption: false,
      );

      expect(
        rows.map((r) => r.kind),
        everyElement(CallerOverlayRowKind.candidate),
      );
      expect(rows, hasLength(2));
    });

    test('σημαδεύονται μόνο όσοι έχουν το τηλέφωνο της φόρμας', () {
      final owner = UserModel(
        id: 3,
        firstName: 'Ελένη',
        lastName: 'Διακομοπούλου',
        phones: const ['2534'],
      );
      final rows = callerOverlayRows(
        selectedCaller: null,
        candidates: [owner, nikos],
        showUnknownOption: true,
        phone: '2534',
      );

      expect(rows.map((r) => r.isPhoneOwner).toList(), [true, false, false]);
    });

    test('με λιγότερα από 3 ψηφία δεν σημαδεύεται κανείς', () {
      final owner = UserModel(id: 3, firstName: 'Ελένη', phones: const ['25']);
      final rows = callerOverlayRows(
        selectedCaller: null,
        candidates: [owner],
        showUnknownOption: false,
        phone: '25',
      );

      expect(rows.single.isPhoneOwner, isFalse);
    });
  });

  group('callerAutocompleteOptions', () {
    List<UserModel> noSearch(String _) =>
        fail('Με υποψηφίους η αναζήτηση μένει μέσα σε αυτούς');

    test('με υποψηφίους: φιλτράρει μόνο αυτούς', () {
      expect(
        callerAutocompleteOptions(
          query: 'νικ',
          candidates: [maria, nikos],
          searchUsers: noSearch,
        ),
        ['Νίκος Παππάς (Ακτινολογικό)'],
      );
    });

    test(
      'άδειο κείμενο: καμία πρόταση — με υποψηφίους τους δείχνει η μικρή λίστα',
      () {
        expect(
          callerAutocompleteOptions(
            query: '  ',
            candidates: [maria, nikos],
            searchUsers: noSearch,
          ),
          isEmpty,
          reason:
              'Τα βελάκια δεν διαλέγουν υπάλληλο από λίστα που δεν φαίνεται',
        );
      },
    );

    test('χωρίς υποψηφίους: ψάχνει στον κατάλογο και κρατά ό,τι ταιριάζει', () {
      String? asked;
      final options = callerAutocompleteOptions(
        query: ' ψαρ ',
        candidates: const [],
        searchUsers: (q) {
          asked = q;
          return [maria, nikos];
        },
      );

      expect(asked, 'ψαρ');
      expect(options, ['Μαρία Ψαρρά (Μικροβιολογικό)']);
    });
  });

  group('resolveCallerSelection', () {
    test(
      'ταυτίζει υποψήφιο με το πλήρες κείμενο της γραμμής ή με το όνομα',
      () {
        for (final selection in [
          'Νίκος Παππάς (Ακτινολογικό)',
          'Νίκος Παππάς',
        ]) {
          expect(
            resolveCallerSelection(
              selection,
              candidates: [maria, nikos],
              searchUsers: null,
            )?.id,
            2,
          );
        }
      },
    );

    test('στον κατάλογο προηγείται το ακριβές πλήρες κείμενο της γραμμής', () {
      final namesake = _user(3, 'Μαρία', 'Ψαρρά', department: 'Ταμείο');
      String? asked;
      final found = resolveCallerSelection(
        'Μαρία Ψαρρά (Ταμείο)',
        candidates: const [],
        searchUsers: (q) {
          asked = q;
          return [maria, namesake];
        },
      );

      expect(asked, 'Μαρία Ψαρρά', reason: 'Ψάχνει χωρίς το τμήμα');
      expect(found?.id, 3);
    });

    test('χωρίς κατάλογο και χωρίς υποψήφιο: κανείς', () {
      expect(
        resolveCallerSelection(
          'Μαρία Ψαρρά',
          candidates: [nikos],
          searchUsers: null,
        ),
        isNull,
      );
    });
  });

  group('callerPreviewText', () {
    test('γράφει μόνο το όνομα του υπαλλήλου, και τον Άγνωστο ως έχει', () {
      expect(
        callerPreviewText(
          'Νίκος Παππάς (Ακτινολογικό)',
          candidates: [nikos],
          searchUsers: null,
        ),
        'Νίκος Παππάς',
      );
      expect(
        callerPreviewText(
          kCallerUnknownOption,
          candidates: [nikos],
          searchUsers: null,
        ),
        kCallerUnknownOption,
      );
    });
  });
}
