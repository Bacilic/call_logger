// Προειδοποίηση επεξεργασίας κλήσης που έχει φύγει στο Lansweeper.
//
// Το μήνυμα οφείλει να ονομάζει ΠΟΙΟ ticket, όχι τη λογική συνθήκη που το
// ενεργοποίησε — και ο αριθμός να ανοίγει το ticket στον περιηγητή.
//
//   flutter test test/features/history/lansweeper_edit_warning_test.dart --timeout 30s

import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_edit_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import 'lansweeper_ticket_link_finders.dart';

const _template = 'https://lansweeper.local/helpdesk/ticket.aspx?tid={tid}';

Future<void> _pumpWarning(
  WidgetTester tester, {
  required String? ticketId,
  String? template = _template,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LansweeperEditWarning(
          ticketId: ticketId,
          ticketViewUrlTemplate: template,
          onClone: () {},
          cloneBusy: false,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('διατύπωση', () {
    test('με αριθμό ticket η φράση ανοίγει για τον σύνδεσμο', () {
      expect(
        lansweeperEditWarningHeadline(ticketId: '17132'),
        'Η κλήση έχει καταχωρηθεί στο Lansweeper — ticket',
        reason: greekExpectMsg(
          'Χωρίς τελεία στο τέλος: ο αριθμός ακολουθεί ως σύνδεσμος',
        ),
      );
    });

    test('χωρίς αριθμό, πλήρης πρόταση χωρίς αναφορά σε ticket', () {
      expect(
        lansweeperEditWarningHeadline(ticketId: null),
        'Η κλήση είναι σημειωμένη ως καταχωρημένη στο Lansweeper.',
      );
      expect(
        lansweeperEditWarningHeadline(ticketId: '   '),
        'Η κλήση είναι σημειωμένη ως καταχωρημένη στο Lansweeper.',
      );
    });

    test('η φράση δεν εκθέτει ποτέ τη λογική συνθήκη του κώδικα', () {
      for (final id in <String?>[null, '17132']) {
        final headline = lansweeperEditWarningHeadline(ticketId: id);
        expect(
          headline.contains(' ή '),
          isFalse,
          reason: greekExpectMsg(
            'Το «έχει ticket Ή κατάσταση sent» ήταν ο τελεστής του if, όχι '
            'μήνυμα προς άνθρωπο',
          ),
        );
        expect(headline.contains('sent'), isFalse);
      }
    });
  });

  group('σύνδεσμος ticket', () {
    testWidgets('ο αριθμός εμφανίζεται ως σύνδεσμος', (tester) async {
      await _pumpWarning(tester, ticketId: '17132');

      expect(
        ticketRendersAsTappableLink(tester, '#17132'),
        isTrue,
        reason: greekExpectMsg('Ο αριθμός ticket πρέπει να πατιέται'),
      );
      expect(find.textContaining('#17132'), findsOneWidget);
      expect(
        find.textContaining('Η κλήση έχει καταχωρηθεί στο Lansweeper'),
        findsOneWidget,
      );
    });

    testWidgets('χωρίς έγκυρο πρότυπο URL, ο αριθμός μένει ορατός ως κείμενο', (
      tester,
    ) async {
      await _pumpWarning(tester, ticketId: '17132', template: '');

      expect(
        ticketRendersAsTappableLink(tester, '#17132'),
        isFalse,
        reason: greekExpectMsg(
          'Σύνδεσμος που δεν οδηγεί πουθενά είναι χειρότερος από απλό κείμενο',
        ),
      );
      expect(
        find.textContaining('#17132'),
        findsOneWidget,
        reason: greekExpectMsg(
          'Ο αριθμός παραμένει η χρήσιμη πληροφορία ακόμα κι αν λείπει η ρύθμιση',
        ),
      );
    });

    testWidgets('χωρίς αριθμό ticket δεν υπάρχει σύνδεσμος', (tester) async {
      await _pumpWarning(tester, ticketId: null);

      expect(ticketRendersAsTappableLink(tester, '#17132'), isFalse);
      expect(find.textContaining('#'), findsNothing);
      expect(find.textContaining('σημειωμένη ως καταχωρημένη'), findsOneWidget);
    });
  });

  testWidgets('η συνέπεια αναφέρεται πάντα, με ή χωρίς ticket', (tester) async {
    await _pumpWarning(tester, ticketId: '17132');
    expect(find.text(kLansweeperEditWarningConsequence), findsOneWidget);

    await _pumpWarning(tester, ticketId: null);
    expect(find.text(kLansweeperEditWarningConsequence), findsOneWidget);
  });
}
