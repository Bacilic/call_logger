// Unit tests: πότε μια διεύθυνση εκθέτει το κλειδί που κουβαλά.
//
//   flutter test test/core/utils/secret_bearing_url_test.dart

import 'package:call_logger/core/utils/secret_bearing_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('εκτεθειμένο μυστικό στη διεύθυνση', () {
    test('http προς διακομιστή του δικτύου: εκτίθεται', () {
      expect(
        urlCarriesSecretUnencrypted('http://10.10.201.22:81/api.aspx'),
        isTrue,
      );
    });

    test('https: δεν εκτίθεται', () {
      expect(
        urlCarriesSecretUnencrypted('https://10.10.201.22:81/api.aspx'),
        isFalse,
      );
    });

    test('κεφαλαία και κενά δεν ξεγελούν τον έλεγχο', () {
      expect(urlCarriesSecretUnencrypted('  HTTP://server/api.aspx  '), isTrue);
    });

    test('κενό πεδίο δεν προειδοποιεί', () {
      expect(urlCarriesSecretUnencrypted(''), isFalse);
      expect(urlCarriesSecretUnencrypted('   '), isFalse);
    });

    test('ημιτελής διεύθυνση υπό πληκτρολόγηση δεν προειδοποιεί', () {
      expect(urlCarriesSecretUnencrypted('10.10.201.22/api.aspx'), isFalse);
      expect(urlCarriesSecretUnencrypted('htt'), isFalse);
    });

    test('πρότυπο με placeholders κρίνεται κανονικά από το σχήμα', () {
      expect(
        urlCarriesSecretUnencrypted(
          'http://gemini.local/v1/models/{μοντέλο}:generateContent'
          '?key={κλειδί API}',
        ),
        isTrue,
      );
      expect(
        urlCarriesSecretUnencrypted(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '{μοντέλο}:generateContent?key={κλειδί API}',
        ),
        isFalse,
      );
    });

    test('τοπικός διακομιστής δεν προειδοποιεί — τίποτα δεν φεύγει', () {
      expect(
        urlCarriesSecretUnencrypted('http://localhost:81/api.aspx'),
        isFalse,
      );
      expect(urlCarriesSecretUnencrypted('http://127.0.0.1/api.aspx'), isFalse);
    });

    test('διακομιστής που αρχίζει με «localhost» ΔΕΝ είναι τοπικός', () {
      expect(
        urlCarriesSecretUnencrypted('http://localhost.example.gr/api.aspx'),
        isTrue,
      );
    });
  });

  group('το μήνυμα προς τον χρήστη', () {
    test('ονομάζει το μυστικό που εκτίθεται', () {
      final warning = insecureSecretUrlWarning(
        'http://10.10.201.22:81/api.aspx',
        secretLabel: 'το κλειδί API',
      );
      expect(warning, isNotNull);
      expect(warning, contains('το κλειδί API'));
      expect(warning, contains('https'));
    });

    test('σιωπά όταν δεν υπάρχει λόγος', () {
      expect(
        insecureSecretUrlWarning(
          'https://10.10.201.22/api.aspx',
          secretLabel: 'το κλειδί API',
        ),
        isNull,
      );
    });
  });
}
