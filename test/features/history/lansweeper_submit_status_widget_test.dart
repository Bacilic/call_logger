// Widget: η ζώνη κατάστασης της αποστολής και το αναδιπλούμενο ιστορικό.
//
// Ελέγχεται η **σύνδεση**, όχι η εμφάνιση (Κ2): ότι η οθόνη λέει τι κάνει η
// αποστολή, ότι το αποτέλεσμα και ο χρόνος μένουν αφού τελειώσει, και ότι το
// ιστορικό δεν καταναλώνει χώρο όταν δεν έχει τίποτα να δείξει.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:call_logger/features/history/models/lansweeper_submit_progress.dart';
import 'package:call_logger/features/history/providers/lansweeper_submit_progress_provider.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_submit_status.dart';
import 'package:call_logger/features/history/widgets/lansweeper/sync_history_list.dart';

Widget _host(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

LansweeperSubmitProgressNotifier _notifier(WidgetTester tester) {
  final element = tester.element(find.byType(Scaffold));
  return ProviderScope.containerOf(
    element,
  ).read(lansweeperSubmitProgressProvider.notifier);
}

void main() {
  group('Ζώνη κατάστασης αποστολής', () {
    testWidgets('χωρίς αποστολή δηλώνει ετοιμότητα', (tester) async {
      await tester.pumpWidget(_host(const LansweeperSubmitStatusBar()));
      expect(find.text('Έτοιμη για αποστολή'), findsOneWidget);
    });

    testWidgets('όσο τρέχει λέει ποιο βήμα και πόσα συνολικά', (tester) async {
      await tester.pumpWidget(_host(const LansweeperSubmitStatusBar()));
      final notifier = _notifier(tester);

      notifier.begin(const [
        LansweeperSubmitStepKeys.requester,
        LansweeperSubmitStepKeys.ticket,
        LansweeperSubmitStepKeys.save,
      ]);
      notifier.stepStarted(LansweeperSubmitStepKeys.ticket);
      await tester.pump();

      expect(
        find.textContaining('Δημιουργία αιτήματος'),
        findsOneWidget,
        reason: 'Η οθόνη ονομάζει το βήμα που τρέχει',
      );
      expect(find.textContaining('βήμα 2 από 3'), findsOneWidget);

      // Το χρονόμετρο σταματά με το κλείσιμο της πορείας — χωρίς αυτό, το τεστ
      // θα τερμάτιζε με ενεργό χρονιστή.
      notifier.finish(success: true, summary: 'Καταχωρήθηκε · αίτημα 17188');
      await tester.pump();
    });

    testWidgets('το αποτέλεσμα και ο χρόνος μένουν μετά το τέλος', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LansweeperSubmitStatusBar()));
      final notifier = _notifier(tester);

      notifier.begin(const [LansweeperSubmitStepKeys.ticket]);
      notifier.stepStarted(LansweeperSubmitStepKeys.ticket);
      notifier.finish(success: true, summary: 'Καταχωρήθηκε · αίτημα 17188');
      await tester.pump();

      expect(find.text('Καταχωρήθηκε · αίτημα 17188'), findsOneWidget);
      expect(
        find.textContaining('δλ'),
        findsOneWidget,
        reason: 'Ο συνολικός χρόνος μένει ορατός αντί να σβήσει',
      );
    });

    testWidgets('η αποτυχία λέει την αιτία της', (tester) async {
      await tester.pumpWidget(_host(const LansweeperSubmitStatusBar()));
      final notifier = _notifier(tester);

      notifier.begin(const [LansweeperSubmitStepKeys.ticket]);
      notifier.stepStarted(LansweeperSubmitStepKeys.ticket);
      notifier.finish(
        success: false,
        summary: 'Αποτυχία στο AddTicket: άκυρος αιτών',
      );
      await tester.pump();

      expect(find.text('Αποτυχία στο AddTicket: άκυρος αιτών'), findsOneWidget);
    });
  });

  group('Πορεία αποστολής', () {
    testWidgets('δεν εμφανίζεται όσο δεν έχει τρέξει τίποτα', (tester) async {
      await tester.pumpWidget(_host(const LansweeperSubmitStepsPanel()));
      expect(find.text('Πορεία αποστολής'), findsNothing);
    });

    testWidgets('δείχνει τα βήματα μόλις ξεκινήσει η αποστολή', (tester) async {
      await tester.pumpWidget(_host(const LansweeperSubmitStepsPanel()));
      final notifier = _notifier(tester);

      notifier.begin(const [
        LansweeperSubmitStepKeys.ticket,
        LansweeperSubmitStepKeys.save,
      ]);
      notifier.stepStarted(LansweeperSubmitStepKeys.ticket);
      // Σκέτο pump: όσο τρέχει η αποστολή γυρίζει ο κυκλικός δείκτης, οπότε
      // δεν υπάρχει «ηρεμία» να περιμένει κανείς.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Πορεία αποστολής'), findsOneWidget);
      expect(find.text('Δημιουργία αιτήματος'), findsOneWidget);
      expect(find.text('Αποθήκευση στη βάση'), findsOneWidget);

      notifier.finish(success: true, summary: 'Καταχωρήθηκε');
      await tester.pumpAndSettle();
    });
  });

  group('Το αποτέλεσμα ανήκει στην κλήση του', () {
    testWidgets('δεν συνοδεύει άλλη κλήση', (tester) async {
      await tester.pumpWidget(
        _host(const LansweeperSubmitStatusBar(selectedCallId: 9)),
      );
      final notifier = _notifier(tester);

      notifier.begin(
        const [LansweeperSubmitStepKeys.ticket],
        callIds: const [5],
      );
      notifier.stepStarted(LansweeperSubmitStepKeys.ticket);
      await tester.pump();

      expect(
        find.textContaining('Δημιουργία αιτήματος'),
        findsOneWidget,
        reason: 'Όσο τρέχει, η αποστολή φαίνεται όποια κλήση κι αν βλέπεις',
      );

      notifier.finish(success: true, summary: 'Καταχωρήθηκε · αίτημα 17789');
      await tester.pump();

      expect(
        find.textContaining('Καταχωρήθηκε'),
        findsNothing,
        reason:
            'Η κλήση 9 δεν στάλθηκε ποτέ — δεν επιτρέπεται να φαίνεται '
            'καταχωρημένη',
      );
      expect(find.text('Έτοιμη για αποστολή'), findsOneWidget);
    });

    testWidgets('φαίνεται στην κλήση που στάλθηκε', (tester) async {
      await tester.pumpWidget(
        _host(const LansweeperSubmitStatusBar(selectedCallId: 5)),
      );
      final notifier = _notifier(tester);

      notifier.begin(
        const [LansweeperSubmitStepKeys.ticket],
        callIds: const [5, 6],
      );
      notifier.stepStarted(LansweeperSubmitStepKeys.ticket);
      notifier.finish(success: true, summary: 'Καταχωρήθηκε · αίτημα 17789');
      await tester.pump();

      expect(find.text('Καταχωρήθηκε · αίτημα 17789'), findsOneWidget);
    });

    testWidgets('χωρίς επιλογή το αποτέλεσμα μένει να διαβαστεί', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LansweeperSubmitStatusBar()));
      final notifier = _notifier(tester);

      notifier.begin(
        const [LansweeperSubmitStepKeys.ticket],
        callIds: const [5],
      );
      notifier.stepStarted(LansweeperSubmitStepKeys.ticket);
      notifier.finish(success: true, summary: 'Καταχωρήθηκε · αίτημα 17789');
      await tester.pump();

      expect(
        find.text('Καταχωρήθηκε · αίτημα 17789'),
        findsOneWidget,
        reason: 'Μετά την καταχώρηση οι κλήσεις αποεπιλέγονται μόνες τους',
      );
    });

    testWidgets('η πορεία εξαφανίζεται σε άλλη κλήση', (tester) async {
      await tester.pumpWidget(
        _host(const LansweeperSubmitStepsPanel(selectedCallId: 9)),
      );
      final notifier = _notifier(tester);

      notifier.begin(
        const [LansweeperSubmitStepKeys.ticket],
        callIds: const [5],
      );
      notifier.stepStarted(LansweeperSubmitStepKeys.ticket);
      notifier.finish(success: true, summary: 'Καταχωρήθηκε');
      await tester.pumpAndSettle();

      expect(find.text('Πορεία αποστολής'), findsNothing);
    });
  });

  group('Ιστορικό tickets', () {
    testWidgets('κενό: μία γραμμή που δεν ανοίγει', (tester) async {
      await tester.pumpWidget(
        _host(const SyncHistoryList(links: <Map<String, dynamic>>[])),
      );

      expect(find.text('Ιστορικό tickets'), findsOneWidget);
      expect(find.text('κανένα'), findsOneWidget);
      expect(
        find.byType(ExpansionTile),
        findsNothing,
        reason: 'Χωρίς περιεχόμενο δεν προσφέρεται άνοιγμα',
      );
    });

    testWidgets('με εγγραφές: κλειστό, ανοίγει με κλικ', (tester) async {
      await tester.pumpWidget(
        _host(
          const SyncHistoryList(
            links: <Map<String, dynamic>>[
              {
                'external_id': '17188',
                'created_at': '2026-09-01 14:58',
                'metadata': '{"mode":"api_workflow"}',
              },
            ],
          ),
        ),
      );

      expect(find.text('1 καταχώρηση'), findsOneWidget);
      expect(
        find.text('Ticket: 17188'),
        findsNothing,
        reason: 'Το ιστορικό ξεκινά αναδιπλωμένο',
      );

      await tester.tap(find.text('Ιστορικό tickets'));
      await tester.pumpAndSettle();

      expect(find.text('Ticket: 17188'), findsOneWidget);
    });
  });
}
