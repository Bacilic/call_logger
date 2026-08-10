// Unit tests: ο κοινός κανόνας κατάστασης Lansweeper.
//
// Ο κανόνας ζούσε ως ιδιωτική συνάρτηση μέσα σε αρχείο διεπαφής της αναφοράς,
// ενώ το ερώτημα προς τη βάση τον αγνοούσε. Τώρα που τον διαβάζουν και το
// Ιστορικό και η αναφορά, φυλάγεται εδώ.
//
//   flutter test test/features/history/lansweeper_sync_state_test.dart

import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalize', () {
    test('οι γνωστές καταστάσεις περνούν αυτούσιες', () {
      expect(
        LansweeperSyncState.normalize(LansweeperSyncState.sent),
        LansweeperSyncState.sent,
      );
      expect(
        LansweeperSyncState.normalize(LansweeperSyncState.excluded),
        LansweeperSyncState.excluded,
      );
      expect(
        LansweeperSyncState.normalize(LansweeperSyncState.failed),
        LansweeperSyncState.failed,
      );
    });

    test('κενό, null και whitespace σημαίνουν ακαταχώρητη', () {
      expect(LansweeperSyncState.normalize(null), LansweeperSyncState.unsent);
      expect(LansweeperSyncState.normalize(''), LansweeperSyncState.unsent);
      expect(LansweeperSyncState.normalize('   '), LansweeperSyncState.unsent);
      expect(LansweeperSyncState.normalize('\t'), LansweeperSyncState.unsent);
    });

    test('άγνωστη τιμή πέφτει στην ακαταχώρητη, δεν εξαφανίζεται', () {
      // Κλήση που δεν ανήκει σε καμία κατηγορία θα ήταν αόρατη παντού — ούτε
      // στην ουρά της αναφοράς ούτε σε κανένα φίλτρο του Ιστορικού.
      expect(
        LansweeperSyncState.normalize('unknown_state'),
        LansweeperSyncState.unsent,
      );
      expect(
        LansweeperSyncState.normalize('pending'),
        LansweeperSyncState.unsent,
      );
    });
  });

  group('isQueued', () {
    test('η ακαταχώρητη και η αποτυχημένη μένουν να γίνουν', () {
      expect(LansweeperSyncState.isQueued(LansweeperSyncState.unsent), isTrue);
      expect(LansweeperSyncState.isQueued(LansweeperSyncState.failed), isTrue);
    });

    test('η καταχωρημένη και η εξαιρεμένη έχουν τακτοποιηθεί', () {
      expect(LansweeperSyncState.isQueued(LansweeperSyncState.sent), isFalse);
      expect(
        LansweeperSyncState.isQueued(LansweeperSyncState.excluded),
        isFalse,
      );
    });

    test('η άγνωστη και η κενή μπαίνουν στην ουρά', () {
      expect(LansweeperSyncState.isQueued(null), isTrue);
      expect(LansweeperSyncState.isQueued(''), isTrue);
      expect(LansweeperSyncState.isQueued('orphan'), isTrue);
    });
  });

  group('ετικέτες', () {
    test('κάθε κατάσταση έχει ενικό και πληθυντικό', () {
      expect(LansweeperSyncState.label(LansweeperSyncState.unsent), 'Ακαταχώρητη');
      expect(LansweeperSyncState.label(LansweeperSyncState.sent), 'Καταχωρημένη');
      expect(
        LansweeperSyncState.label(LansweeperSyncState.excluded),
        'Εξαιρεμένη',
      );
      expect(
        LansweeperSyncState.label(LansweeperSyncState.failed),
        'Αποτυχημένη',
      );

      expect(
        LansweeperSyncState.labelPlural(LansweeperSyncState.unsent),
        'Ακαταχώρητες',
      );
      expect(
        LansweeperSyncState.labelPlural(LansweeperSyncState.excluded),
        'Εξαιρεμένες',
      );
    });

    test('η κενή κατάσταση παίρνει την ετικέτα της ακαταχώρητης', () {
      expect(LansweeperSyncState.label(null), 'Ακαταχώρητη');
      expect(LansweeperSyncState.labelPlural(''), 'Ακαταχώρητες');
    });
  });
}
