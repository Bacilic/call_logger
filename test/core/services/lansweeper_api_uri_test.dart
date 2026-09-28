// Unit tests: η συναρμολόγηση της διεύθυνσης κλήσης του Lansweeper Ticket API.
//
// Μέχρι σήμερα ο κώδικας αυτός δεν εκτελούνταν σε κανένα τεστ: τα τεστ της
// αποστολής περνούν ψεύτικο αποστολέα και παρακάμπτουν τη συναρμολόγηση.
//
//   flutter test test/core/services/lansweeper_api_uri_test.dart

import 'package:call_logger/core/services/lansweeper_api_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('συναρμολόγηση διεύθυνσης', () {
    test('βάζει action και κλειδί στις παραμέτρους', () {
      final result = buildLansweeperApiActionUri(
        apiUrl: 'http://server:81/api.aspx',
        apiKey: 'κλειδί-δοκιμής',
        action: 'AddTicket',
      );

      expect(result.problem, isNull);
      expect(result.uri!.queryParameters['action'], 'AddTicket');
      expect(result.uri!.queryParameters['key'], 'κλειδί-δοκιμής');
      expect(result.uri!.host, 'server');
      expect(result.uri!.port, 81);
      expect(result.uri!.path, '/api.aspx');
    });

    test('κρατά παραμέτρους που υπήρχαν ήδη στη διεύθυνση', () {
      final result = buildLansweeperApiActionUri(
        apiUrl: 'http://server/api.aspx?site=2',
        apiKey: 'κ',
        action: 'AddTicket',
      );

      expect(result.uri!.queryParameters['site'], '2');
      expect(result.uri!.queryParameters['action'], 'AddTicket');
    });

    test('τα επιπλέον πεδία επικαλύπτουν τα πάντα', () {
      final result = buildLansweeperApiActionUri(
        apiUrl: 'http://server/api.aspx?action=Παλιό',
        apiKey: 'κ',
        action: 'AddTicket',
        extraQueryParams: const {'action': 'GetTicket', 'tid': '42'},
      );

      expect(result.uri!.queryParameters['action'], 'GetTicket');
      expect(result.uri!.queryParameters['tid'], '42');
    });

    test('κενά γύρω από τη διεύθυνση και το κλειδί αγνοούνται', () {
      final result = buildLansweeperApiActionUri(
        apiUrl: '  http://server/api.aspx  ',
        apiKey: '  κ  ',
        action: 'AddTicket',
      );

      expect(result.problem, isNull);
      expect(result.uri!.queryParameters['key'], 'κ');
    });
  });

  group('τι εμποδίζει την κλήση', () {
    test('χωρίς διεύθυνση', () {
      final result = buildLansweeperApiActionUri(
        apiUrl: '   ',
        apiKey: 'κ',
        action: 'AddTicket',
      );
      expect(result.uri, isNull);
      expect(result.problem, LansweeperApiUriProblem.missingUrl);
    });

    test('χωρίς κλειδί', () {
      final result = buildLansweeperApiActionUri(
        apiUrl: 'http://server/api.aspx',
        apiKey: '',
        action: 'AddTicket',
      );
      expect(result.uri, isNull);
      expect(result.problem, LansweeperApiUriProblem.missingKey);
    });

    test('διεύθυνση χωρίς σχήμα ή διακομιστή', () {
      for (final bad in const ['server/api.aspx', 'http://', '::::']) {
        final result = buildLansweeperApiActionUri(
          apiUrl: bad,
          apiKey: 'κ',
          action: 'AddTicket',
        );
        expect(
          result.problem,
          LansweeperApiUriProblem.invalidUrl,
          reason: 'η «$bad» δεν είναι κλήσιμη διεύθυνση',
        );
      }
    });

    test('η έλλειψη διεύθυνσης προηγείται της έλλειψης κλειδιού', () {
      final result = buildLansweeperApiActionUri(
        apiUrl: '',
        apiKey: '',
        action: 'AddTicket',
      );
      expect(result.problem, LansweeperApiUriProblem.missingUrl);
    });
  });
}
