// Το υπόμνημα κάτω από το «Αναγνωριστικό Lansweeper» της καρτέλας υπαλλήλου.
//
// Τέσσερις καταστάσεις με ΣΕΙΡΑ: αν η τιμή δεν πρόκειται να χρησιμοποιηθεί,
// κάθε άλλη συμβουλή είναι χαμένος κόπος — το «το έγραψες λάθος, μήπως
// εννοούσες Χ;» στέλνει τον χρήστη να διορθώσει κάτι που δεν διαβάζει κανείς.
//
//   flutter test test/core/services/lansweeper_identity_field_hint_test.dart

import 'package:call_logger/core/services/lansweeper_identity_diagnosis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const domain = 'gnk';

  group('τμήμα εκτός Lansweeper', () {
    test('το μήνυμα λέει ότι δεν θα χρησιμοποιηθεί, χωρίς τόνο λάθους', () {
      final hint = lansweeperIdentityFieldHint(
        participatesInLansweeper: false,
        identity: r'gnk\g.damorakis',
        referenceDomain: domain,
      );

      expect(hint.text, contains('δεν θα χρησιμοποιηθεί'));
      expect(hint.tone, LansweeperIdentityHintTone.neutral);
    });

    test('υπερισχύει της διάγνωσης λάθους μορφής', () {
      // Ο Δαμωράκης της DataMed έχει γράψει χαλασμένο αναγνωριστικό. Το να
      // του ζητηθεί διόρθωση θα ήταν συμβουλή για τιμή που δεν διαβάζεται.
      final hint = lansweeperIdentityFieldHint(
        participatesInLansweeper: false,
        identity: 'gnk\\',
        referenceDomain: domain,
      );

      expect(hint.text, contains('δεν θα χρησιμοποιηθεί'));
      expect(hint.tone, isNot(LansweeperIdentityHintTone.error));
    });

    test('εμφανίζεται και με κενό πεδίο', () {
      final hint = lansweeperIdentityFieldHint(
        participatesInLansweeper: false,
        identity: '',
        referenceDomain: domain,
      );

      expect(hint.text, contains('δεν θα χρησιμοποιηθεί'));
    });
  });

  group('τμήμα του νοσοκομείου — η σημερινή συμπεριφορά μένει', () {
    test('χαλασμένη μορφή κρατά τον τόνο λάθους', () {
      final hint = lansweeperIdentityFieldHint(
        participatesInLansweeper: true,
        identity: 'gnk\\',
        referenceDomain: domain,
      );

      expect(hint.tone, LansweeperIdentityHintTone.error);
      expect(hint.text, isNot(contains('δεν θα χρησιμοποιηθεί')));
    });

    test('έγκυρη ταυτότητα με ξένο τομέα μένει ήπια υποψία', () {
      final hint = lansweeperIdentityFieldHint(
        participatesInLansweeper: true,
        identity: r'allo\g.damorakis',
        referenceDomain: domain,
      );

      expect(hint.tone, LansweeperIdentityHintTone.suspicion);
    });

    test('έγκυρη ταυτότητα στον δικό μας τομέα δίνει την υπόσχεση', () {
      final hint = lansweeperIdentityFieldHint(
        participatesInLansweeper: true,
        identity: r'gnk\g.damorakis',
        referenceDomain: domain,
      );

      expect(hint.tone, LansweeperIdentityHintTone.neutral);
      expect(hint.text, contains('αιτών'));
    });

    test('κενό πεδίο δίνει την υπόσχεση, όχι σφάλμα', () {
      final hint = lansweeperIdentityFieldHint(
        participatesInLansweeper: true,
        identity: '   ',
        referenceDomain: domain,
      );

      expect(hint.tone, LansweeperIdentityHintTone.neutral);
      expect(hint.text, contains('αιτών'));
    });
  });
}
