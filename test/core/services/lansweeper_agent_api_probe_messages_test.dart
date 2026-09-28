// Unit tests: τα μηνύματα του «Ελέγχου πράκτορα API» πριν φτάσει στο δίκτυο.
//
// Ο έλεγχος δοκιμάζει ό,τι έχει πληκτρολογηθεί στην οθόνη, πριν αποθηκευτεί —
// γι' αυτό μιλά με τη γλώσσα του πεδίου («Συμπληρώστε…») και όχι με τη γλώσσα
// της ρύθμισης («Δεν έχει οριστεί…»), που ανήκει στην αποστολή αιτήματος.
//
//   flutter test test/core/services/lansweeper_agent_api_probe_messages_test.dart

import 'package:call_logger/core/services/lansweeper_agent_api_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('τα κενά πεδία απαντώνται χωρίς να αγγιχτεί το δίκτυο', () {
    test('χωρίς διεύθυνση', () async {
      final result = await LansweeperAgentApiProbe.verify(
        apiUrl: '   ',
        apiKey: 'κ',
        agentUsername: 'gnk\\v.drosos',
      );
      expect(result.ok, isFalse);
      expect(result.message, 'Συμπληρώστε το URL API (api.aspx).');
    });

    test('χωρίς κλειδί', () async {
      final result = await LansweeperAgentApiProbe.verify(
        apiUrl: 'http://server/api.aspx',
        apiKey: '',
        agentUsername: 'gnk\\v.drosos',
      );
      expect(result.ok, isFalse);
      expect(result.message, 'Συμπληρώστε το Lansweeper API key.');
    });

    test('χωρίς πράκτορα', () async {
      final result = await LansweeperAgentApiProbe.verify(
        apiUrl: 'http://server/api.aspx',
        apiKey: 'κ',
        agentUsername: '  ',
      );
      expect(result.ok, isFalse);
      expect(result.message, 'Συμπληρώστε το όνομα πράκτορα (username).');
    });

    test(
      'η διεύθυνση ρωτιέται πρώτη, μετά το κλειδί, μετά ο πράκτορας',
      () async {
        final result = await LansweeperAgentApiProbe.verify(
          apiUrl: '',
          apiKey: '',
          agentUsername: '',
        );
        expect(result.message, 'Συμπληρώστε το URL API (api.aspx).');
      },
    );

    test('άκυρη διεύθυνση αναφέρεται όπως γράφτηκε', () async {
      final result = await LansweeperAgentApiProbe.verify(
        apiUrl: 'server-χωρίς-σχήμα/api.aspx',
        apiKey: 'κ',
        agentUsername: 'gnk\\v.drosos',
      );
      expect(result.ok, isFalse);
      expect(
        result.message,
        'Μη έγκυρο Lansweeper API URL: server-χωρίς-σχήμα/api.aspx',
      );
    });
  });
}
