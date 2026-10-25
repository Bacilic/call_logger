// Το υπόμνημα κάτω από το «Αναγνωριστικό Lansweeper» της καρτέλας υπαλλήλου,
// και η σημείωση που παίρνει τη θέση του πεδίου σε υπάλληλο εταιρείας ή
// εξωτερικής μονάδας.
//
//   flutter test test/core/services/lansweeper_identity_field_hint_test.dart

import 'package:call_logger/core/services/lansweeper_identity_diagnosis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const domain = 'gnk';

  group('τμήμα εκτός Lansweeper — σημείωση στη θέση του πεδίου', () {
    test('το φυλαγμένο αναγνωριστικό αναφέρεται αυτούσιο', () {
      expect(
        lansweeperIdentityHiddenNote(r' gnk\g.damorakis '),
        r'Ο υπάλληλος έχει αναγνωριστικό στο νοσοκομείο gnk\g.damorakis',
      );
    });

    test('χωρίς αναγνωριστικό δεν υπάρχει σημείωση', () {
      expect(lansweeperIdentityHiddenNote(''), isNull);
      expect(lansweeperIdentityHiddenNote('   '), isNull);
    });
  });

  group('τμήμα του νοσοκομείου', () {
    test('χαλασμένη μορφή κρατά τον τόνο λάθους', () {
      final hint = lansweeperIdentityFieldHint(
        identity: 'gnk\\',
        referenceDomain: domain,
      );

      expect(hint.tone, LansweeperIdentityHintTone.error);
    });

    test('έγκυρη ταυτότητα με ξένο τομέα μένει ήπια υποψία', () {
      final hint = lansweeperIdentityFieldHint(
        identity: r'allo\g.damorakis',
        referenceDomain: domain,
      );

      expect(hint.tone, LansweeperIdentityHintTone.suspicion);
    });

    test('έγκυρη ταυτότητα στον δικό μας τομέα δίνει την υπόσχεση', () {
      final hint = lansweeperIdentityFieldHint(
        identity: r'gnk\g.damorakis',
        referenceDomain: domain,
      );

      expect(hint.tone, LansweeperIdentityHintTone.neutral);
      expect(hint.text, contains('αιτών'));
    });

    test('κενό πεδίο δίνει την υπόσχεση, όχι σφάλμα', () {
      final hint = lansweeperIdentityFieldHint(
        identity: '   ',
        referenceDomain: domain,
      );

      expect(hint.tone, LansweeperIdentityHintTone.neutral);
      expect(hint.text, contains('αιτών'));
    });
  });
}
