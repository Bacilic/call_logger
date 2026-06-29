import 'package:call_logger/core/utils/user_identity_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserIdentityNormalizer unified matching', () {
    test('matches both name orders for structured person', () {
      const first = 'Γιώργος';
      const last = 'Παπαδόπουλος';

      expect(
        UserIdentityNormalizer.personMatchesIdentityKeys(
          personFirstName: first,
          personLastName: last,
          sourceKeys: UserIdentityNormalizer.matchingIdentityKeysFromFreeText(
            'Παπαδόπουλος Γιώργος',
          ),
        ),
        isTrue,
      );
      expect(
        UserIdentityNormalizer.personMatchesIdentityKeys(
          personFirstName: first,
          personLastName: last,
          sourceKeys: UserIdentityNormalizer.matchingIdentityKeysFromFreeText(
            'Γιώργος Παπαδόπουλος',
          ),
        ),
        isTrue,
      );
    });

    test('single token matches person with either first or last field', () {
      final keys = UserIdentityNormalizer.matchingIdentityKeysFromFreeText(
        'Παπαδόπουλος',
      );

      expect(
        UserIdentityNormalizer.personMatchesIdentityKeys(
          personFirstName: 'Παπαδόπουλος',
          personLastName: '',
          sourceKeys: keys,
        ),
        isTrue,
      );
      expect(
        UserIdentityNormalizer.personMatchesIdentityKeys(
          personFirstName: '',
          personLastName: 'Παπαδόπουλος',
          sourceKeys: keys,
        ),
        isTrue,
      );
    });

    test('identity key stable without redundant sigma folding', () {
      final withFinalSigma = UserIdentityNormalizer.identityKeyForPerson(
        'Γιάννης',
        '',
      );
      final withLowerSigma = UserIdentityNormalizer.identityKeyForPerson(
        'Γιάννησ',
        '',
      );

      expect(withFinalSigma, equals(withLowerSigma));
      expect(withFinalSigma, contains('γιαννησ'));
    });
  });
}
