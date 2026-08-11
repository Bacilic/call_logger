import 'package:call_logger/core/services/lansweeper_ticket_requester_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lansweeperAgentValueLooksLikeEmail', () {
    test('κενή τιμή → false', () {
      expect(lansweeperAgentValueLooksLikeEmail(''), isFalse);
    });

    test('τιμή μόνο με κενά → false', () {
      expect(lansweeperAgentValueLooksLikeEmail('   '), isFalse);
    });

    test(r'άκυρο με μόνο @ χωρίς TLD (π.χ. dro@fd) → false', () {
      expect(lansweeperAgentValueLooksLikeEmail('dro@fd'), isFalse);
    });

    test('σκέτο @ χωρίς τοπικό μέρος → false', () {
      expect(lansweeperAgentValueLooksLikeEmail('@hospkorinthos.gr'), isFalse);
    });

    test('έγκυρο email → true', () {
      expect(
        lansweeperAgentValueLooksLikeEmail('v.drosos@hospkorinthos.gr'),
        isTrue,
      );
    });

    test('έγκυρο email με trim → true', () {
      expect(
        lansweeperAgentValueLooksLikeEmail('  v.drosos@hospkorinthos.gr  '),
        isTrue,
      );
    });

    test('μη λατινικοί χαρακτήρες (ελληνικά) → false', () {
      expect(
        lansweeperAgentValueLooksLikeEmail('ΒασίληςΔρόσος@γγγ.κλ'),
        isFalse,
      );
    });
  });

  group('lansweeperAgentValueLooksLikeDisplayName', () {
    test('κενή τιμή → false', () {
      expect(lansweeperAgentValueLooksLikeDisplayName(''), isFalse);
    });

    test('τιμή μόνο με κενά → false', () {
      expect(lansweeperAgentValueLooksLikeDisplayName('   '), isFalse);
    });

    test(r'domain\username → false', () {
      expect(
        lansweeperAgentValueLooksLikeDisplayName(r'gnk\v.drosos'),
        isFalse,
      );
    });

    test('έγκυρο email → false', () {
      expect(
        lansweeperAgentValueLooksLikeDisplayName('v.drosos@hospkorinthos.gr'),
        isFalse,
      );
    });

    test('σκέτο display name → true', () {
      expect(
        lansweeperAgentValueLooksLikeDisplayName('Βασίλης Δρόσος'),
        isTrue,
      );
    });

    test('τιμή με trim γύρω από σκέτο όνομα → true', () {
      expect(
        lansweeperAgentValueLooksLikeDisplayName('  Βασίλης Δρόσος  '),
        isTrue,
      );
    });

    test(r'άκυρο pseudo-email (dro@fd) → true (προειδοποίηση)', () {
      expect(lansweeperAgentValueLooksLikeDisplayName('dro@fd'), isTrue);
    });

    test('ελληνικό pseudo-email → true (προειδοποίηση)', () {
      expect(
        lansweeperAgentValueLooksLikeDisplayName('ΒασίληςΔρόσος@γγγ.κλ'),
        isTrue,
      );
    });

    test(
      r'ονομασία κολλημένη μπροστά («Γραφείο Λοιμώξεων gnk\x») → true — '
      'το Lansweeper δεν θα βρει τέτοιον χρήστη',
      () {
        expect(
          lansweeperAgentValueLooksLikeDisplayName(
            r'Γραφείο Λοιμώξεων gnk\loimokseis1',
          ),
          isTrue,
        );
      },
    );

    test('κενό μέσα στο όνομα χρήστη → true (προειδοποίηση)', () {
      expect(
        lansweeperAgentValueLooksLikeDisplayName(r'gnk\p koutra'),
        isTrue,
      );
    });

    test('καθαρό domain\\username χωρίς κενά → false (καμία προειδοποίηση)', () {
      expect(
        lansweeperAgentValueLooksLikeDisplayName(r'gnk\loimokseis1'),
        isFalse,
      );
    });
  });

  group('lansweeperAgentAsMatchingRequesterFields', () {
    test('domain username maps to Username and AgentUsername', () {
      expect(
        lansweeperAgentAsMatchingRequesterFields(r'gnk\v.drosos'),
        <String, String>{
          'Username': r'gnk\v.drosos',
          'AgentUsername': r'gnk\v.drosos',
        },
      );
    });

    test('email maps to Email and AgentEmail', () {
      expect(
        lansweeperAgentAsMatchingRequesterFields('v.drosos@hospkorinthos.gr'),
        <String, String>{
          'Email': 'v.drosos@hospkorinthos.gr',
          'AgentEmail': 'v.drosos@hospkorinthos.gr',
        },
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        lansweeperAgentAsMatchingRequesterFields('  gnk\\v.drosos  '),
        <String, String>{
          'Username': r'gnk\v.drosos',
          'AgentUsername': r'gnk\v.drosos',
        },
      );
    });

    test(r'άκυρο dro@fd δεν χαρτογραφείται ως Email', () {
      expect(
        lansweeperAgentAsMatchingRequesterFields('dro@fd'),
        <String, String>{'Username': 'dro@fd', 'AgentUsername': 'dro@fd'},
      );
    });

    test('ελληνικό pseudo-email δεν χαρτογραφείται ως Email', () {
      expect(
        lansweeperAgentAsMatchingRequesterFields('ΒασίληςΔρόσος@γγγ.κλ'),
        <String, String>{
          'Username': 'ΒασίληςΔρόσος@γγγ.κλ',
          'AgentUsername': 'ΒασίληςΔρόσος@γγγ.κλ',
        },
      );
    });
  });

  group('lansweeperRequesterAndAgentFields — αιτών ≠ πράκτορας', () {
    test('δύο ταυτότητες τομέα: Username=αιτών, AgentUsername=πράκτορας', () {
      expect(
        lansweeperRequesterAndAgentFields(
          requester: r'gnk\d.brami',
          agent: r'gnk\v.drosos',
        ),
        <String, String>{
          'Username': r'gnk\d.brami',
          'AgentUsername': r'gnk\v.drosos',
        },
      );
    });

    test('μικτά είδη: αιτών email + πράκτορας τομέα, το καθένα στο πεδίο του', () {
      expect(
        lansweeperRequesterAndAgentFields(
          requester: 'dbrami@hospkorinthos.gr',
          agent: r'gnk\v.drosos',
        ),
        <String, String>{
          'Email': 'dbrami@hospkorinthos.gr',
          'AgentUsername': r'gnk\v.drosos',
        },
      );
    });

    test('αντίστροφα μικτά: αιτών τομέα + πράκτορας email', () {
      expect(
        lansweeperRequesterAndAgentFields(
          requester: r'gnk\d.brami',
          agent: 'v.drosos@hospkorinthos.gr',
        ),
        <String, String>{
          'Username': r'gnk\d.brami',
          'AgentEmail': 'v.drosos@hospkorinthos.gr',
        },
      );
    });
  });

  group('lansweeperSearchUsersParamsFor', () {
    test(r'τομέας\όνομα → Username + UserDomain χωριστά', () {
      expect(lansweeperSearchUsersParamsFor(r'gnk\d.brami'), <String, String>{
        'Username': 'd.brami',
        'UserDomain': 'gnk',
      });
    });

    test('email → μόνο Email', () {
      expect(
        lansweeperSearchUsersParamsFor('dbrami@hospkorinthos.gr'),
        <String, String>{'Email': 'dbrami@hospkorinthos.gr'},
      );
    });

    test('σκέτο κείμενο → Username ως έχει', () {
      expect(lansweeperSearchUsersParamsFor('d.brami'), <String, String>{
        'Username': 'd.brami',
      });
    });
  });
}
