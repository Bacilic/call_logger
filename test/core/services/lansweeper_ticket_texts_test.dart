import 'dart:convert';

import 'package:call_logger/core/services/lansweeper_ticket_texts.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _link(String ticketId, Map<String, Object?>? metadata) => {
  'external_id': ticketId,
  'metadata': metadata == null ? null : jsonEncode(metadata),
};

void main() {
  group('LansweeperTicketTexts.latestFromLinks', () {
    test('τα κείμενα που καταγράφει μια αποστολή διαβάζονται πίσω ίδια', () {
      const sent = LansweeperTicketTexts(
        subject: 'Τίτλος',
        problem: 'Πρόβλημα',
      );

      final read = LansweeperTicketTexts.latestFromLinks([
        _link('18308', {'mode': 'api_workflow', ...sent.toMetadata()}),
      ], '18308');

      expect(read?.subject, 'Τίτλος');
      expect(read?.problem, 'Πρόβλημα');
    });

    test(
      'κρατά τον νεότερο σύνδεσμο του ΙΔΙΟΥ αιτήματος και προσπερνά όσους δεν κατέγραψαν κείμενα',
      () {
        final read = LansweeperTicketTexts.latestFromLinks([
          _link('18308', {'mode': 'manual'}),
          _link('17000', {'ticketSubject': 'Άλλο', 'ticketProblem': 'Άλλο'}),
          _link('18308', {'ticketSubject': 'Νέος', 'ticketProblem': 'Νέο'}),
          _link('18308', {'ticketSubject': 'Παλιός', 'ticketProblem': 'Παλιό'}),
        ], '18308');

        expect(read?.subject, 'Νέος');
      },
    );

    test('χωρίς καταγραφή ή με χαλασμένα μεταδεδομένα: «δεν ξέρουμε»', () {
      expect(
        LansweeperTicketTexts.latestFromLinks([
          _link('18308', null),
          {'external_id': '18308', 'metadata': '{χαλασμένο'},
        ], '18308'),
        isNull,
      );
    });
  });
}
