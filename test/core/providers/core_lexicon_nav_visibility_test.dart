// Ορατότητα του στοιχείου πλοήγησης «Λεξικό».
//
// Η ρητή επιλογή του χρήστη νικά. Παλιότερα ο κανόνας έκανε μια εξαίρεση «για
// το καλό του»: όταν δεν είχε φορτωθεί λεξικό-πυρήνας, κρατούσε το εικονίδιο
// ορατό ώστε να μη χαθεί η προειδοποίηση. Το αποτέλεσμα ήταν ρύθμιση που δεν
// υπάκουε — και μάλιστα ακριβώς στην κατάσταση όπου το εικονίδιο φορούσε το
// θαυμαστικό. Η προειδοποίηση ζει στις Ρυθμίσεις, δίπλα στον διακόπτη.
//
//   flutter test test/core/providers/core_lexicon_nav_visibility_test.dart

import 'package:call_logger/core/providers/core_lexicon_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('κλειστός ορθογραφικός έλεγχος: το Λεξικό δεν έχει νόημα', () {
    expect(
      isDictionaryNavVisible(enableSpellCheck: false, showDictionaryNav: true),
      isFalse,
    );
  });

  test('η απόκρυψη ισχύει ΚΑΙ όταν λείπει το λεξικό-πυρήνας', () {
    expect(
      isDictionaryNavVisible(enableSpellCheck: true, showDictionaryNav: false),
      isFalse,
      reason:
          'Ο χρήστης ζήτησε να φύγει το εικονίδιο. Μια προειδοποίηση δεν του '
          'δίνει δικαίωμα να αγνοήσει τη ρύθμιση — το κείμενό της γράφεται '
          'ήδη στις Ρυθμίσεις, εκεί που πατήθηκε ο διακόπτης.',
    );
  });

  test('χωρίς απόκρυψη το Λεξικό φαίνεται κανονικά', () {
    expect(
      isDictionaryNavVisible(enableSpellCheck: true, showDictionaryNav: true),
      isTrue,
    );
  });
}
