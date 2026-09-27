// Unit tests: το κλειδί της ΤΝ δεν ταξιδεύει μέσα στη διεύθυνση.
//
// Η διεύθυνση καταλήγει σε μηνύματα σφάλματος, σε αρχεία καταγραφής και στην
// οθόνη των Ρυθμίσεων (το πρότυπο το επεξεργάζεται ο χρήστης). Όσο το κλειδί
// ζει μέσα της, ταξιδεύει παντού μαζί της.
//
//   flutter test test/core/services/gemini_key_stays_out_of_url_test.dart

import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _kKey = 'ΚΛΕΙΔΙ-ΔΟΚΙΜΗΣ-0000';

void main() {
  group('η διεύθυνση κλήσης', () {
    test('δεν περιέχει το κλειδί, ούτε ως παράμετρο ούτε ως κείμενο', () {
      final target = GeminiTicketService.resolveCallTarget(
        endpoint: kDefaultGeminiEndpoint,
        apiKey: _kKey,
        primaryModel: 'gemini-flash-latest',
      );

      expect(target.uri.toString().contains(_kKey), isFalse);
      expect(target.uri.queryParameters.containsKey('key'), isFalse);
      expect(target.uri.path, contains('gemini-flash-latest'));
    });

    test('παλιό πρότυπο με γραμμένο κλειδί μέσα του καθαρίζεται κι αυτό', () {
      final target = GeminiTicketService.resolveCallTarget(
        endpoint:
            'https://generativelanguage.googleapis.com/v1beta/models/'
            'gemini-flash-latest:generateContent?key=ΠΑΛΙΟ-ΓΡΑΜΜΕΝΟ-ΚΛΕΙΔΙ',
        apiKey: _kKey,
      );

      expect(target.uri.queryParameters.containsKey('key'), isFalse);
      expect(
        target.uri.toString().contains('ΠΑΛΙΟ-ΓΡΑΜΜΕΝΟ-ΚΛΕΙΔΙ'),
        isFalse,
        reason: 'ένα κλειδί γραμμένο με το χέρι εκτίθεται το ίδιο',
      );
    });

    test('οι άλλες παράμετροι της διεύθυνσης δεν χάνονται', () {
      final target = GeminiTicketService.resolveCallTarget(
        endpoint:
            'https://example.gr/v1/models/'
            '$kGeminiPrimaryModelPlaceholder:generateContent'
            '?key=$kGeminiApiKeyPlaceholder&alt=json',
        apiKey: _kKey,
        primaryModel: 'gemini-test-model',
      );

      expect(target.uri.queryParameters['alt'], 'json');
      expect(target.uri.queryParameters.containsKey('key'), isFalse);
    });

    test('διεύθυνση χωρίς παράμετρο κλειδιού δεν αποκτά ερωτηματικό', () {
      final target = GeminiTicketService.resolveCallTarget(
        endpoint:
            'https://example.gr/v1/models/'
            '$kGeminiPrimaryModelPlaceholder:generateContent',
        apiKey: _kKey,
        primaryModel: 'gemini-test-model',
      );

      expect(target.uri.hasQuery, isFalse);
      expect(target.uri.host, 'example.gr');
      expect(target.uri.path, contains('gemini-test-model'));
    });
  });

  group('οι κεφαλίδες', () {
    test('κουβαλούν το κλειδί στη θέση που ορίζει η Google', () {
      final target = GeminiTicketService.resolveCallTarget(
        endpoint: kDefaultGeminiEndpoint,
        apiKey: '  $_kKey  ',
      );

      expect(target.headers['x-goog-api-key'], _kKey);
      expect(target.headers['Content-Type'], 'application/json');
    });
  });

  group('η λίστα μοντέλων', () {
    test('χτίζεται με τον ίδιο κανόνα', () {
      final target = GeminiTicketService.modelsListTarget(apiKey: _kKey);

      expect(target.uri.queryParameters.containsKey('key'), isFalse);
      expect(target.uri.toString().contains(_kKey), isFalse);
      expect(target.headers['x-goog-api-key'], _kKey);
    });

    test('η σελιδοποίηση διατηρείται', () {
      final target = GeminiTicketService.modelsListTarget(
        apiKey: _kKey,
        pageToken: 'σελίδα-2',
      );

      expect(target.uri.queryParameters['pageToken'], 'σελίδα-2');
      expect(target.uri.queryParameters.containsKey('key'), isFalse);
    });
  });
}
