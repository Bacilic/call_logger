// Η γραμμή σύνοψης της αναζήτησης Λάμπας: δύο σκέλη (εξοπλισμός + οντότητες
// χωρίς εξοπλισμό), με σωστό ενικό/πληθυντικό σε κάθε σκέλος χωριστά.
//
//   flutter test test/features/lamp/controllers/lamp_search_outcome_message_test.dart

import 'package:call_logger/features/lamp/controllers/lamp_search_outcome_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  String? msg({
    int equipment = 0,
    int? equipmentShown,
    int unlinked = 0,
    int? unlinkedShown,
  }) => lampSearchOutcomeMessage(
    equipmentTotal: equipment,
    equipmentShown: equipmentShown ?? equipment,
    unlinkedTotal: unlinked,
    unlinkedShown: unlinkedShown ?? unlinked,
  );

  test('και τα δύο σκέλη — το κύριο σενάριο', () {
    expect(
      msg(equipment: 35, unlinked: 4),
      'Βρέθηκαν 35 εξοπλισμοί και 4 οντότητες χωρίς εξοπλισμό.',
    );
  });

  test('μόνο εξοπλισμός', () {
    expect(msg(equipment: 35), 'Βρέθηκαν 35 εξοπλισμοί.');
  });

  test('μόνο ασύνδετα — δηλώνει ρητά ότι εξοπλισμός δεν βρέθηκε', () {
    expect(
      msg(unlinked: 202),
      'Βρέθηκαν 202 οντότητες χωρίς εξοπλισμό. Κανένας εξοπλισμός.',
    );
  });

  test('τίποτα → null (το κεντρικό μήνυμα αναλαμβάνει)', () {
    expect(msg(), isNull);
  });

  group('ενικός', () {
    test('ένας εξοπλισμός', () {
      expect(msg(equipment: 1), 'Βρέθηκε 1 εξοπλισμός.');
    });

    test('μία οντότητα', () {
      expect(
        msg(unlinked: 1),
        'Βρέθηκε 1 οντότητα χωρίς εξοπλισμό. Κανένας εξοπλισμός.',
      );
    });

    test('ένα και ένα', () {
      expect(
        msg(equipment: 1, unlinked: 1),
        'Βρέθηκε 1 εξοπλισμός και 1 οντότητα χωρίς εξοπλισμό.',
      );
    });

    test('μικτό πλήθος: το ρήμα γίνεται πληθυντικός', () {
      expect(
        msg(equipment: 1, unlinked: 4),
        'Βρέθηκαν 1 εξοπλισμός και 4 οντότητες χωρίς εξοπλισμό.',
        reason: greekExpectMsg(
          '«Βρέθηκε 1 εξοπλισμός και 4 οντότητες» είναι λάθος ελληνικά — με '
          'πολλαπλά υποκείμενα το ρήμα πάει στον πληθυντικό',
        ),
      );
    });
  });

  group('κομμένη εμφάνιση', () {
    test('κομμένος εξοπλισμός', () {
      expect(
        msg(equipment: 500, equipmentShown: 100, unlinked: 4),
        'Βρέθηκαν 500 εξοπλισμοί και 4 οντότητες χωρίς εξοπλισμό. '
        'Εμφανίζονται οι πρώτοι 100 εξοπλισμοί.',
      );
    });

    test('κομμένα ασύνδετα', () {
      expect(
        msg(unlinked: 202, unlinkedShown: 100),
        'Βρέθηκαν 202 οντότητες χωρίς εξοπλισμό. Κανένας εξοπλισμός. '
        'Εμφανίζονται οι πρώτες 100 οντότητες.',
        reason: greekExpectMsg(
          'Με ενεργό φίλτρο και κενή αναζήτηση οι 202 ιδιοκτήτες κόβονται '
          'στο όριο — χωρίς τη σημείωση, η λίστα μοιάζει πλήρης ενώ δεν είναι',
        ),
      );
    });

    test('κομμένα και τα δύο', () {
      expect(
        msg(
          equipment: 500,
          equipmentShown: 100,
          unlinked: 300,
          unlinkedShown: 100,
        ),
        'Βρέθηκαν 500 εξοπλισμοί και 300 οντότητες χωρίς εξοπλισμό. '
        'Εμφανίζονται οι πρώτοι 100 εξοπλισμοί. '
        'Εμφανίζονται οι πρώτες 100 οντότητες.',
      );
    });
  });
}
