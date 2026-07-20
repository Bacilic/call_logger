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
        <String, String>{
          'Username': 'dro@fd',
          'AgentUsername': 'dro@fd',
        },
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
}
