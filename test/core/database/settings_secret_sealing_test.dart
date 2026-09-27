// Unit tests: το σφράγισμα των μυστικών που ζουν μέσα στη βάση.
//
//   flutter test test/core/database/settings_secret_sealing_test.dart

import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/database/settings_secret_sealing.dart';
import 'package:call_logger/core/services/overridable_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('σφράγισμα και ξεσφράγισμα', () {
    test('η τιμή γυρίζει πίσω ακριβώς όπως δόθηκε', () {
      for (final plain in const [
        '00000000-dead-beef-cafe-000000000000',
        'κλειδί με ελληνικά και κενά',
        'a',
        'σύμβολα !@#\$%^&*()_+{}|:"<>?',
      ]) {
        expect(unsealSettingValue(sealSettingValue(plain)), plain);
      }
    });

    test('η αποθηκευμένη μορφή ΔΕΝ περιέχει το αρχικό κείμενο', () {
      const plain = 'ΜΥΣΤΙΚΟ-ΚΛΕΙΔΙ-1234';
      final sealed = sealSettingValue(plain);

      expect(sealed.contains(plain), isFalse);
      expect(sealed.contains('ΜΥΣΤΙΚΟ'), isFalse);
      expect(sealed.contains('1234'), isFalse);
      expect(isSealedSettingValue(sealed), isTrue);
    });

    test('ίδια τιμή δίνει διαφορετική σφραγίδα κάθε φορά', () {
      const plain = 'ίδιο κλειδί';
      expect(sealSettingValue(plain), isNot(sealSettingValue(plain)));
    });

    test('κενή τιμή μένει κενή — «δεν έχει οριστεί» δεν είναι μυστικό', () {
      expect(sealSettingValue(''), '');
      expect(isSealedSettingValue(''), isFalse);
    });
  });

  group('παλιές και χαλασμένες τιμές', () {
    test('παλιά ακάλυπτη τιμή διαβάζεται ως έχει', () {
      const legacy = '00000000-dead-beef-cafe-000000000000';
      expect(isSealedSettingValue(legacy), isFalse);
      expect(unsealSettingValue(legacy), legacy);
    });

    test('αλλοιωμένη σφραγίδα δίνει null, όχι σκουπίδι', () {
      final sealed = sealSettingValue('κλειδί');
      final tampered = '${sealed.substring(0, sealed.length - 4)}AAAA';
      expect(unsealSettingValue(tampered), isNull);
    });

    test('σφραγίδα με άκυρο περιεχόμενο δίνει null', () {
      expect(unsealSettingValue('$kSettingSealPrefixόχι-base64!!'), isNull);
      expect(unsealSettingValue('${kSettingSealPrefix}AAAA'), isNull);
      expect(unsealSettingValue(kSettingSealPrefix), isNull);
    });
  });

  group('ποια κλειδιά σφραγίζονται', () {
    test('τα δύο κοινά κλειδιά API', () {
      expect(kSealedSettingKeys, contains(kLansweeperApiKeySettingKey));
      expect(kSealedSettingKeys, contains(kGeminiApiKeySettingKey));
    });

    test(
      'το προσωπικό κλειδί ΤΝ — η ονομασία δεν επιτρέπεται να αποκλίνει',
      () {
        expect(
          kSealedOperatorSettingKeys,
          contains(OverridableSettingKeys.geminiApiKey.key),
          reason: 'το σφράγισμα δείχνει σε κλειδί που δεν γράφεται πουθενά',
        );
      },
    );

    test('το URL δεν είναι μυστικό και δεν σφραγίζεται', () {
      expect(kSealedSettingKeys, isNot(contains(kLansweeperApiUrlSettingKey)));
      expect(kSealedSettingKeys, isNot(contains(kGeminiEndpointSettingKey)));
    });
  });
}
