// Πώς χτίζεται η λίστα του φίλτρου «χρήστης» — καθαρή λογική, χωρίς οθόνη.
//
// Εκκρεμότητες και Ιστορικό ρωτούν διαφορετικούς πίνακες αλλά χτίζουν την ίδια
// λίστα. Πριν, ο κώδικας ήταν γραμμένος δύο φορές· εδώ φυλάγεται μία.
//
//   flutter test test/features/operators/owner_filter_options_test.dart

import 'package:call_logger/core/models/owner_filter.dart';
import 'package:call_logger/features/operators/utils/owner_filter_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const names = {11: 'Βασίλης', 22: 'Βλάσης', 33: 'Αντωνία'};

  List<String> labelsOf(List<OwnerFilterOption> options) =>
      options.map((o) => o.label).toList();

  group('buildOwnerFilterOptions', () {
    test('«Όλοι» πρώτο, τα ονόματα αλφαβητικά', () {
      final options = buildOwnerFilterOptions(
        ownerIds: {11, 22, 33},
        names: names,
        hasUnassigned: false,
      );

      expect(labelsOf(options), ['Όλοι', 'Αντωνία', 'Βασίλης', 'Βλάσης']);
    });

    test('«Χωρίς χρήστη» μπαίνει τελευταίο, μόνο όταν υπάρχουν τέτοιες', () {
      final withNone = buildOwnerFilterOptions(
        ownerIds: {11},
        names: names,
        hasUnassigned: true,
      );
      expect(labelsOf(withNone), ['Όλοι', 'Βασίλης', 'Χωρίς χρήστη']);

      final withoutNone = buildOwnerFilterOptions(
        ownerIds: {11},
        names: names,
        hasUnassigned: false,
      );
      expect(labelsOf(withoutNone), ['Όλοι', 'Βασίλης']);
    });

    test('χρήστης εκτός καταλόγου δεν κρύβεται', () {
      final options = buildOwnerFilterOptions(
        ownerIds: {99},
        names: names,
        hasUnassigned: false,
      );

      expect(
        labelsOf(options),
        ['Όλοι', 'Χρήστης #99'],
        reason:
            'Οι εγγραφές του υπάρχουν και πρέπει να μπορούν να βρεθούν — η '
            'ίδια εφεδρεία με τα σήματα των καρτών, γραμμένη μία φορά.',
      );
    });

    test('όσο ο κατάλογος δεν έχει φορτώσει, τα ids μένουν επιλέξιμα', () {
      final options = buildOwnerFilterOptions(
        ownerIds: {11},
        names: null,
        hasUnassigned: false,
      );

      expect(labelsOf(options), ['Όλοι', 'Χρήστης #11']);
    });

    test('χωρίς κανέναν χρήστη μένει μόνο το «Όλοι»', () {
      final options = buildOwnerFilterOptions(
        ownerIds: const {},
        names: names,
        hasUnassigned: false,
      );

      expect(labelsOf(options), ['Όλοι']);
    });

    test(
      'η πρώτη επιλογή είναι πάντα το «Όλοι» ως τιμή, όχι μόνο ως κείμενο',
      () {
        final options = buildOwnerFilterOptions(
          ownerIds: {11},
          names: names,
          hasUnassigned: true,
        );

        expect(options.first.value.isEveryone, isTrue);
        expect(options.last.value, OwnerFilter.unassigned);
      },
    );
  });
}
