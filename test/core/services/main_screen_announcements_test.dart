// Ειδοποιήσεις που περιμένουν την κύρια οθόνη, αντί να ανοίγουν πάνω από την
// επιλογή χρήστη ή την κάρτα εκκίνησης.
//
//   flutter test test/core/services/main_screen_announcements_test.dart

import 'package:call_logger/core/services/main_screen_announcements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(MainScreenAnnouncements.resetForTest);
  tearDown(MainScreenAnnouncements.resetForTest);

  test('πριν από την κύρια οθόνη η ειδοποίηση περιμένει', () {
    // Περιστατικό 28/10/2026: ο διάλογος του φακέλου αντιγράφων άνοιγε πάνω
    // από το «Ποιος χρησιμοποιεί την εφαρμογή;».
    var shown = 0;

    MainScreenAnnouncements.announce(() => shown++);

    expect(shown, 0);
  });

  test('μόλις εμφανιστεί η κύρια οθόνη, η ειδοποίηση βγαίνει μία φορά', () {
    var shown = 0;
    MainScreenAnnouncements.announce(() => shown++);

    MainScreenAnnouncements.open();
    MainScreenAnnouncements.open();

    expect(shown, 1);
  });

  test('με την κύρια οθόνη μπροστά, η ειδοποίηση βγαίνει αμέσως', () {
    var shown = 0;
    MainScreenAnnouncements.open();

    MainScreenAnnouncements.announce(() => shown++);

    expect(shown, 1);
  });

  test('όταν η κύρια οθόνη φύγει, η επόμενη ειδοποίηση περιμένει ξανά', () {
    // Αλλαγή βάσης: η κύρια οθόνη ξαναστήνεται, και στο μεταξύ μπορεί να
    // περάσουν πάλι επιλογή χρήστη και κάρτα εκκίνησης.
    var shown = 0;
    MainScreenAnnouncements.open();
    MainScreenAnnouncements.close();

    MainScreenAnnouncements.announce(() => shown++);
    expect(shown, 0);

    MainScreenAnnouncements.open();
    expect(shown, 1);
  });
}
