// Οι προειδοποιήσεις μιας καταχώρησης Lansweeper, όπως ξαναδιαβάζονται από το
// αποθηκευμένο `metadata`.
//
// Δύο πράγματα φυλάει αυτό το αρχείο: ότι καμία μορφή σκουπιδιού στη στήλη δεν
// ρίχνει την οθόνη, και το συμβόλαιο «μετράει μόνο η τελευταία καταχώρηση του
// ticket» — αλλιώς μια επανυποβολή που πέτυχε καθαρά θα συνέχιζε να δείχνει το
// παράπονο της προηγούμενης.
//
//   flutter test test/features/history/services/lansweeper_submission_warnings_test.dart

import 'dart:convert';

import 'package:call_logger/features/history/services/lansweeper_submission_warnings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

Map<String, dynamic> link({
  required String externalId,
  List<String>? warnings,
  Object? rawMetadata,
  bool omitMetadata = false,
}) {
  return <String, dynamic>{
    'external_id': externalId,
    if (!omitMetadata)
      'metadata':
          rawMetadata ??
          jsonEncode(<String, dynamic>{
            'mode': 'api_workflow',
            'warnings': ?warnings,
          }),
  };
}

void main() {
  group('lansweeperWarningsFromMetadata — καμία μορφή δεν σκάει', () {
    test('null και κενό κείμενο δίνουν κενή λίστα', () {
      expect(lansweeperWarningsFromMetadata(null), isEmpty);
      expect(lansweeperWarningsFromMetadata(''), isEmpty);
      expect(lansweeperWarningsFromMetadata('   '), isEmpty);
    });

    test('άκυρο JSON δίνει κενή λίστα αντί για εξαίρεση', () {
      expect(
        lansweeperWarningsFromMetadata('{όχι json'),
        isEmpty,
        reason: greekExpectMsg(
          'Μια χαλασμένη γραμμή ιστορικού δεν επιτρέπεται να ρίξει την οθόνη',
        ),
      );
    });

    test('JSON χωρίς το κλειδί των προειδοποιήσεων δίνει κενή λίστα', () {
      expect(
        lansweeperWarningsFromMetadata('{"mode":"api_workflow"}'),
        isEmpty,
      );
    });

    test('τιμή που δεν είναι λίστα αγνοείται', () {
      expect(
        lansweeperWarningsFromMetadata('{"warnings":"μία προειδοποίηση"}'),
        isEmpty,
        reason: greekExpectMsg(
          'Κείμενο αντί για λίστα σημαίνει άγνωστη μορφή, όχι μία προειδοποίηση',
        ),
      );
    });

    test(
      'κενά και λευκά στοιχεία πετιούνται, τα υπόλοιπα μένουν με τη σειρά',
      () {
        final warnings = lansweeperWarningsFromMetadata(
          jsonEncode(<String, dynamic>{
            'warnings': <dynamic>['  πρώτη  ', '', '   ', 'δεύτερη'],
          }),
        );
        expect(warnings, <String>['πρώτη', 'δεύτερη']);
      },
    );

    test('δέχεται και έτοιμο Map, όχι μόνο κείμενο JSON', () {
      expect(
        lansweeperWarningsFromMetadata(<String, dynamic>{
          'warnings': <dynamic>['η προειδοποίηση'],
        }),
        <String>['η προειδοποίηση'],
      );
    });
  });

  group('lansweeperWarningsForTicket — μετράει η τελευταία του ticket', () {
    test('επιστρέφονται μόνο οι προειδοποιήσεις του ζητούμενου ticket', () {
      final links = <Map<String, dynamic>>[
        link(externalId: '17679', warnings: <String>['του 17679']),
        link(externalId: '17132', warnings: <String>['του 17132']),
      ];
      expect(
        lansweeperWarningsForTicket(links: links, ticketId: '17132'),
        <String>['του 17132'],
      );
    });

    test('ticket κενό ή null δίνει κενή λίστα', () {
      final links = <Map<String, dynamic>>[
        link(externalId: '17679', warnings: <String>['του 17679']),
      ];
      expect(
        lansweeperWarningsForTicket(links: links, ticketId: null),
        isEmpty,
      );
      expect(
        lansweeperWarningsForTicket(links: links, ticketId: '  '),
        isEmpty,
      );
    });

    test('ticket που δεν υπάρχει στο ιστορικό δίνει κενή λίστα', () {
      final links = <Map<String, dynamic>>[
        link(externalId: '17679', warnings: <String>['του 17679']),
      ];
      expect(
        lansweeperWarningsForTicket(links: links, ticketId: '99999'),
        isEmpty,
      );
    });

    test(
      'καθαρή επανυποβολή σβήνει το παράπονο της προηγούμενης προσπάθειας',
      () {
        // Οι γραμμές έρχονται από τη νεότερη προς την παλαιότερη.
        final links = <Map<String, dynamic>>[
          link(externalId: '17679'),
          link(externalId: '17679', warnings: <String>['ο αιτών δεν βρέθηκε']),
        ];
        expect(
          lansweeperWarningsForTicket(links: links, ticketId: '17679'),
          isEmpty,
          reason: greekExpectMsg(
            'Η τελευταία καταχώρηση πέτυχε καθαρά — το παλιό παράπονο δεν ισχύει πια',
          ),
        );
      },
    );

    test('γραμμή χωρίς καθόλου metadata δεν σκάει', () {
      final links = <Map<String, dynamic>>[
        link(externalId: '17679', omitMetadata: true),
      ];
      expect(
        lansweeperWarningsForTicket(links: links, ticketId: '17679'),
        isEmpty,
      );
    });

    test(
      'τα κενά γύρω από τον αριθμό ticket δεν εμποδίζουν την αντιστοίχιση',
      () {
        final links = <Map<String, dynamic>>[
          link(externalId: ' 17679 ', warnings: <String>['η προειδοποίηση']),
        ];
        expect(
          lansweeperWarningsForTicket(links: links, ticketId: '17679 '),
          <String>['η προειδοποίηση'],
        );
      },
    );
  });

  group('lansweeperSubmitSnackBarText', () {
    test('χωρίς προειδοποιήσεις το μήνυμα μένει αυτούσιο', () {
      expect(
        lansweeperSubmitSnackBarText(
          baseMessage: 'Καταχώρηση επιτυχής. Ticket: 17679',
          warnings: const <String>[],
        ),
        'Καταχώρηση επιτυχής. Ticket: 17679',
      );
    });

    test('κάθε προειδοποίηση παίρνει δική της γραμμή, κάτω από το μήνυμα', () {
      expect(
        lansweeperSubmitSnackBarText(
          baseMessage: 'Καταχώρηση επιτυχής. Ticket: 17679',
          warnings: const <String>['πρώτη', 'δεύτερη'],
        ),
        'Καταχώρηση επιτυχής. Ticket: 17679\nπρώτη\nδεύτερη',
      );
    });
  });

  group('lansweeperSubmitBaseMessage', () {
    test('νέο αίτημα, μία κλήση: το γνωστό μήνυμα με τον αριθμό', () {
      expect(
        lansweeperSubmitBaseMessage(
          ticketId: '17679',
          ticketCreated: true,
          markedCalls: 1,
        ),
        'Καταχώρηση επιτυχής. Ticket: 17679',
      );
    });

    test('υπάρχον αίτημα, μία κλήση: λέει ότι ενημερώθηκε, με τον αριθμό', () {
      final message = lansweeperSubmitBaseMessage(
        ticketId: '17476',
        ticketCreated: false,
        markedCalls: 1,
      );

      expect(message, contains('17476'));
      expect(message, contains('υπάρχον'));
      expect(
        message,
        isNot(contains('Καταχώρηση επιτυχής')),
        reason: 'δεν άνοιξε νέο αίτημα — το μήνυμα δεν το αφήνει να εννοηθεί',
      );
    });

    test('υπάρχον αίτημα, πολλές κλήσεις: πλήθος ΚΑΙ ενημέρωση υπάρχοντος', () {
      final message = lansweeperSubmitBaseMessage(
        ticketId: '17476',
        ticketCreated: false,
        markedCalls: 3,
      );

      expect(message, contains('3 κλήσεις'));
      expect(message, contains('17476'));
      expect(message, contains('υπάρχον'));
    });

    test('νέο αίτημα, πολλές κλήσεις: πλήθος και αριθμός αιτήματος', () {
      expect(
        lansweeperSubmitBaseMessage(
          ticketId: '17679',
          ticketCreated: true,
          markedCalls: 3,
        ),
        '3 κλήσεις επισημάνθηκαν ως καταχωρημένες (ticket #17679).',
      );
    });

    test('χωρίς αριθμό αιτήματος το μήνυμα δεν επινοεί ενημέρωση', () {
      expect(
        lansweeperSubmitBaseMessage(
          ticketId: '   ',
          ticketCreated: false,
          markedCalls: 1,
        ),
        'Καταχώρηση επιτυχής. Ticket: -',
      );
      expect(
        lansweeperSubmitBaseMessage(
          ticketId: '',
          ticketCreated: false,
          markedCalls: 4,
        ),
        '4 κλήσεις επισημάνθηκαν ως καταχωρημένες.',
      );
    });
  });
}
