// Στοχευμένη διάγνωση ταυτότητας Lansweeper: λέμε ΤΙ χάλασε (τομέας ή
// email) — το γενικό μήνυμα μένει μόνο όταν δεν υπάρχει σημάδι πρόθεσης.
// Κανόνες: email_validator (WHATWG/HTML5) για email, κανόνες ονοματοδοσίας
// Microsoft (NetBIOS/sAMAccountName) για τομέα\όνομα.
//
//   flutter test test/core/services/lansweeper_identity_diagnosis_test.dart

import 'package:call_logger/core/services/lansweeper_identity_diagnosis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('έγκυρες ταυτότητες', () {
    test(r'gnk\v.drosos → έγκυρος τομέας\όνομα', () {
      final d = diagnoseLansweeperIdentity(r'gnk\v.drosos');
      expect(d.isValid, isTrue);
      expect(d.kind, LansweeperIdentityKind.domainAccount);
    });

    test('v.drosos@hospkorinthos.gr → έγκυρο email', () {
      final d = diagnoseLansweeperIdentity('v.drosos@hospkorinthos.gr');
      expect(d.isValid, isTrue);
      expect(d.kind, LansweeperIdentityKind.email);
    });

    test('κενή τιμή = «χωρίς ταυτότητα», ποτέ λάθος', () {
      expect(diagnoseLansweeperIdentity('').isValid, isTrue);
      expect(diagnoseLansweeperIdentity('   ').isValid, isTrue);
    });
  });

  group('προσπάθεια τομέα\\όνομα — στοχευμένα λάθη', () {
    test('ξεχασμένο «=» πριν από έγκυρη ουρά → πρόταση με το πλήρες κείμενο',
        () {
      final d = diagnoseLansweeperIdentity(
        r'Γιατρός Τεπ Παθολογικού2 gnk\TepPath2',
      );
      expect(d.isValid, isFalse);
      expect(d.problem, contains('λείπει το «=»'));
      expect(
        d.suggestion,
        r'Γράψτε: Γιατρός Τεπ Παθολογικού2 = gnk\TepPath2',
      );
    });

    test('κενά χωρίς έγκυρη ουρά → μήνυμα για τα κενά, χωρίς πρόταση', () {
      final d = diagnoseLansweeperIdentity(r'gnk\Tep Path Κείμενο');
      expect(d.isValid, isFalse);
      expect(d.problem, contains('κενά'));
      expect(d.suggestion, isNull);
    });

    test(r'mad\fdf.rrg\56 → περισσότερες από μία «\»', () {
      final d = diagnoseLansweeperIdentity(r'mad\fdf.rrg\56');
      expect(d.isValid, isFalse);
      expect(d.problem, contains('περισσότερες από μία'));
    });

    test('λείπει σκέλος πριν/μετά την «\\»', () {
      expect(
        diagnoseLansweeperIdentity(r'\tep1').problem,
        contains('Λείπει ο τομέας'),
      );
      expect(
        diagnoseLansweeperIdentity(r'gnk\').problem,
        contains('Λείπει το όνομα χρήστη'),
      );
    });

    test('τελεία στον τομέα (FQDN) → σύντομη μορφή NetBIOS', () {
      final d = diagnoseLansweeperIdentity(r'gnk.local\v.drosos');
      expect(d.isValid, isFalse);
      expect(d.problem, contains('σύντομη μορφή'));
    });

    test('απαγορευμένος χαρακτήρας Microsoft στο όνομα χρήστη', () {
      final d = diagnoseLansweeperIdentity(r'gnk\v=drosos');
      expect(d.isValid, isFalse);
      expect(d.problem, contains('«=»'));
    });

    test('όρια μήκους: τομέας >15, όνομα >20 (όρια των Windows)', () {
      expect(
        diagnoseLansweeperIdentity(
          r'averylongdomain16\user',
        ).problem,
        contains('15'),
      );
      expect(
        diagnoseLansweeperIdentity(
          r'gnk\averyverylongusername21',
        ).problem,
        contains('20'),
      );
    });
  });

  group('προσπάθεια email — στοχευμένα λάθη', () {
    test('path@ gnk.g → περιέχει κενό', () {
      final d = diagnoseLansweeperIdentity('path@ gnk.g');
      expect(d.kind, LansweeperIdentityKind.email);
      expect(d.problem, contains('κενό'));
    });

    test('dro@fd → ο τομέας δεν μοιάζει πλήρης', () {
      final d = diagnoseLansweeperIdentity('dro@fd');
      expect(d.problem, contains('δεν μοιάζει πλήρης'));
    });

    test('λείπει σκέλος πριν/μετά το «@»', () {
      expect(
        diagnoseLansweeperIdentity('@gnk.gr').problem,
        contains('λείπει το όνομα'),
      );
      expect(
        diagnoseLansweeperIdentity('vd@').problem,
        contains('λείπει ο τομέας'),
      );
    });

    test('ελληνικοί χαρακτήρες → μη λατινικοί', () {
      final d = diagnoseLansweeperIdentity('ΒασίληςΔρόσος@γγγ.κλ');
      expect(d.isValid, isFalse);
      expect(d.problem, contains('λατινικά'));
    });
  });

  group('χωρίς σημάδι πρόθεσης → το γενικό μήνυμα, μόνο τότε', () {
    test('555 και σκέτο κείμενο', () {
      for (final value in ['555', 'Γραφείο Λοιμώξεων']) {
        final d = diagnoseLansweeperIdentity(value);
        expect(d.kind, LansweeperIdentityKind.unknown);
        expect(d.problem, contains('Δεν μοιάζει ούτε με'));
      }
    });

    test('και «\\» και «@» μαζί → ασαφές', () {
      final d = diagnoseLansweeperIdentity(r'gnk\vd@gnk.gr');
      expect(d.problem, contains('και «\\» και «@»'));
    });
  });

  group('lansweeperReferenceDomain — το μέτρο σύγκρισης', () {
    test('πράκτορας «τομέας\\όνομα» → ο τομέας του, χωρίς ψηφοφορία', () {
      expect(
        lansweeperReferenceDomain(agentIdentity: r'gnk\v.drosos'),
        'gnk',
      );
    });

    test('πράκτορας email → ο πλειοψηφικός τομέας του καταλόγου', () {
      // Το πραγματικό σενάριο: ο πράκτορας είναι καταχωρημένος ως email και
      // δεν κουβαλά τομέα NetBIOS — μιλούν τα υπάρχοντα αναγνωριστικά.
      expect(
        lansweeperReferenceDomain(
          agentIdentity: 'v.drosos@hospkorinthos.gr',
          knownIdentities: [r'gnk\bio1', r'gnk\bio2', r'3gnk\TepPath1'],
        ),
        'gnk',
      );
    });

    test('χωρίς 2 ψήφους ή με ισοπαλία → κανένα μέτρο σύγκρισης', () {
      expect(
        lansweeperReferenceDomain(knownIdentities: [r'gnk\bio1']),
        isNull,
      );
      expect(
        lansweeperReferenceDomain(
          knownIdentities: [r'gnk\a', r'gnk\b', r'mad\a', r'mad\b'],
        ),
        isNull,
      );
      expect(lansweeperReferenceDomain(), isNull);
    });

    test('άκυρες/email ταυτότητες δεν ψηφίζουν', () {
      expect(
        lansweeperReferenceDomain(
          knownIdentities: [
            r'gnk\bio1',
            r'gnk\bio2',
            'a@gnk.gr',
            'Γραφείο Λοιμώξεων',
            r'mad\fdf\56',
          ],
        ),
        'gnk',
      );
    });
  });

  group('lansweeperDomainMismatchHint — ήπια υποψία τομέα (πορτοκαλί)', () {
    test('3gnk έναντι συνηθισμένου gnk → υποψία τυπογραφικού', () {
      final hint = lansweeperDomainMismatchHint(r'3gnk\TepPath1', 'gnk');
      expect(hint, isNotNull);
      expect(hint, contains('«3gnk»'));
      expect(hint, contains('«gnk»'));
    });

    test('ίδιος τομέας (αδιάφορα πεζά/κεφαλαία) → καμία υποψία', () {
      expect(lansweeperDomainMismatchHint(r'GNK\TepPath1', 'gnk'), isNull);
    });

    test('χωρίς μέτρο σύγκρισης ή για email/άκυρη τιμή → καμία υποψία', () {
      expect(lansweeperDomainMismatchHint(r'3gnk\a', null), isNull);
      expect(lansweeperDomainMismatchHint(r'3gnk\a', ''), isNull);
      expect(lansweeperDomainMismatchHint('a@gnk.gr', 'gnk'), isNull);
      expect(lansweeperDomainMismatchHint('Γραφείο', 'gnk'), isNull);
    });
  });
}
