// Η μνήμη του σταθμού: ποιοι έχουν διαλέξει ταυτότητα σε αυτόν τον υπολογιστή.
//
//   flutter test test/core/services/workstation_operators_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/workstation_operators.dart';
import 'package:flutter_test/flutter_test.dart';

Operator _operator(
  String name, {
  bool isActive = true,
  int? id,
  String? account,
}) => Operator(
  id: id,
  displayName: name,
  windowsAccount: account,
  isActive: isActive,
  createdAt: DateTime(2026),
);

/// Ο υπολογιστής του Βλάση: το προφίλ του είναι δεμένο στον λογαριασμό του.
final _vlasis = _operator('Βλάσης', id: 2, account: 'vl.oikonomou');
final _vasilis = _operator('Βασίλης', id: 1, account: 'v.drosos');

void main() {
  group('Τι θυμάται ο σταθμός μετά από επιλογή', () {
    test('ο τελευταίος που διάλεξε μπαίνει πρώτος', () {
      expect(rememberedAfterPick(const ['Βασίλης'], 'Μαρία'), [
        'Μαρία',
        'Βασίλης',
      ]);
    });

    test('η επανάληψη δεν διπλασιάζει, ανεβάζει', () {
      expect(rememberedAfterPick(const ['Μαρία', 'Βασίλης'], 'Βασίλης'), [
        'Βασίλης',
        'Μαρία',
      ]);
    });

    test('τόνοι και κεφαλαία δεν φτιάχνουν δεύτερο άνθρωπο', () {
      // Αλλιώς ο σταθμός θα «θυμόταν δύο» και θα ρωτούσε χωρίς λόγο.
      expect(rememberedAfterPick(const ['βασιλησ'], 'Βασίλης'), ['Βασίλης']);
    });

    test('κενό όνομα δεν αγγίζει τη μνήμη', () {
      expect(rememberedAfterPick(const ['Βασίλης'], '   '), ['Βασίλης']);
    });

    test('η λίστα δεν μεγαλώνει χωρίς τέλος', () {
      var names = const <String>[];
      for (var i = 0; i < maxRememberedWorkstationOperators + 5; i++) {
        names = rememberedAfterPick(names, 'Χρήστης $i');
      }

      expect(names, hasLength(maxRememberedWorkstationOperators));
      expect(names.first, 'Χρήστης ${maxRememberedWorkstationOperators + 4}');
    });
  });

  group('Ποιους από τη μνήμη ξέρει η βάση', () {
    test('ταιριάζουν όσοι υπάρχουν, με τη σειρά της μνήμης', () {
      final matched = rememberedWorkstationProfiles(
        const ['Μαρία', 'Βασίλης'],
        [_operator('Βασίλης'), _operator('Μαρία')],
      );

      expect(matched.map((o) => o.displayName), ['Μαρία', 'Βασίλης']);
    });

    test('όνομα που δεν υπάρχει πια αγνοείται', () {
      final matched = rememberedWorkstationProfiles(
        const ['Κάποιος Άλλος', 'Βασίλης'],
        [_operator('Βασίλης')],
      );

      expect(matched.map((o) => o.displayName), ['Βασίλης']);
    });

    test('ο απενεργοποιημένος δεν μετράει', () {
      final matched = rememberedWorkstationProfiles(
        const ['Παλιός', 'Βασίλης'],
        [_operator('Παλιός', isActive: false), _operator('Βασίλης')],
      );

      expect(matched.map((o) => o.displayName), ['Βασίλης']);
    });
  });

  group('Σειρά εμφάνισης στον επιλογέα', () {
    test('πρώτοι όσοι έχουν δουλέψει εδώ, τελευταίος πρώτος', () {
      final ordered = orderProfilesForWorkstation(
        [_operator('Άννα'), _operator('Βασίλης'), _operator('Μαρία')],
        const ['Μαρία', 'Βασίλης'],
      );

      expect(ordered.map((o) => o.displayName), ['Μαρία', 'Βασίλης', 'Άννα']);
    });

    test('χωρίς μνήμη η σειρά της βάσης μένει ως έχει', () {
      final profiles = [_operator('Άννα'), _operator('Βασίλης')];

      expect(
        orderProfilesForWorkstation(
          profiles,
          const [],
        ).map((o) => o.displayName),
        ['Άννα', 'Βασίλης'],
      );
    });

    test('ο άνθρωπος του λογαριασμού Windows μπαίνει πρώτος', () {
      // Ο Βλάσης γύρισε από άδεια. Ο υπολογιστής θυμάται τον Βασίλη, αλλά
      // μπροστά στην οθόνη κάθεται εκείνος — και η λίστα το δείχνει.
      final ordered = orderProfilesForWorkstation(
        [_operator('Άννα'), _vasilis, _vlasis],
        const ['Βασίλης'],
        windowsAccount: 'vl.oikonomou',
      );

      expect(ordered.map((o) => o.displayName), ['Βλάσης', 'Βασίλης', 'Άννα']);
    });

    test('κανείς δεν εμφανίζεται δύο φορές', () {
      final ordered = orderProfilesForWorkstation(
        [_vasilis, _vlasis],
        const ['Βασίλης'],
        windowsAccount: 'v.drosos',
      );

      expect(ordered.map((o) => o.displayName), ['Βασίλης', 'Βλάσης']);
    });
  });

  group('Διαψεύδει ο λογαριασμός Windows τη μνήμη του σταθμού;', () {
    test('ΝΑΙ όταν δείχνει σε άλλον — το σενάριο της επιστροφής από άδεια', () {
      expect(
        workstationMemoryIsContradicted(
          remembered: _vasilis,
          profiles: [_vasilis, _vlasis],
          windowsAccount: 'vl.oikonomou',
        ),
        isTrue,
      );
    });

    test('ΟΧΙ όταν δείχνει στον ίδιο άνθρωπο', () {
      expect(
        workstationMemoryIsContradicted(
          remembered: _vasilis,
          profiles: [_vasilis, _vlasis],
          windowsAccount: 'V.Drosos',
        ),
        isFalse,
      );
    });

    test('ΟΧΙ όταν ο λογαριασμός δεν ανήκει σε κανένα προφίλ', () {
      // Ο κοινόχρηστος σταθμός, όπου τα προφίλ είναι αυτόνομα: η εκκίνηση
      // μένει ακριβώς όπως ήταν.
      expect(
        workstationMemoryIsContradicted(
          remembered: _vasilis,
          profiles: [_vasilis, _vlasis],
          windowsAccount: 'tpo.koino',
        ),
        isFalse,
      );
    });

    test('ΟΧΙ όταν δεν υπάρχει καν λογαριασμός', () {
      expect(
        workstationMemoryIsContradicted(
          remembered: _vasilis,
          profiles: [_vasilis, _vlasis],
          windowsAccount: null,
        ),
        isFalse,
      );
    });

    test('το απενεργοποιημένο προφίλ δεν διαψεύδει κανέναν', () {
      // Ο Βλάσης έφυγε από το νοσοκομείο και το προφίλ του απενεργοποιήθηκε.
      // Ο λογαριασμός μπορεί να επιβιώνει στα Windows — δεν σημαίνει τίποτα.
      final archived = _operator(
        'Βλάσης',
        id: 2,
        account: 'vl.oikonomou',
        isActive: false,
      );
      expect(
        workstationMemoryIsContradicted(
          remembered: _vasilis,
          profiles: [_vasilis, archived],
          windowsAccount: 'vl.oikonomou',
        ),
        isFalse,
      );
    });
  });
}
