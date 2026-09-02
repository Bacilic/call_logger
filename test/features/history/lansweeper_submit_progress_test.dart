// Unit: η πορεία της αποστολής ticket — ποιο βήμα τρέχει, πόσο κράτησε το
// καθένα, πώς σφραγίζεται το αποτέλεσμα.
//
// Καθαρές συναρτήσεις χωρίς διεπαφή (Κ1): η αριθμητική του χρόνου και η
// μετάβαση των καταστάσεων αποδεικνύονται εδώ, ώστε τα widget τεστ να μη
// χρειάζεται να τις ξαναελέγξουν.

import 'package:flutter_test/flutter_test.dart';

import 'package:call_logger/core/services/lansweeper_asset_target.dart';
import 'package:call_logger/core/services/lansweeper_sync_service.dart';
import 'package:call_logger/core/services/lansweeper_ticket_submit_config.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/lansweeper_submit_progress.dart';

CallModel _call() => CallModel(
  id: 1,
  date: '2026-09-02',
  time: '10:00',
  callerText: 'Δοκιμή',
  phoneText: '2997',
  issue: 'δεν ανάβει',
  duration: 180,
);

LansweeperWorkflowRequest _request({
  String solution = 'έγινε επανεκκίνηση',
  String? existingTicketId,
  String? requesterUsername = 'gnk\\s.georgaki',
  LansweeperAssetTarget? assetTarget,
  String? targetState = 'Closed',
  LansweeperTicketSubmitConfig? config,
}) {
  return LansweeperWorkflowRequest(
    call: _call(),
    title: 'Κλήση #1',
    problem: 'δεν ανάβει',
    solution: solution,
    agentUsername: 'gnk\\v.drosos',
    config: config ?? LansweeperTicketSubmitConfig.defaults(),
    customFieldValues: const <String, String>{},
    targetState: targetState,
    existingTicketId: existingTicketId,
    requesterUsername: requesterUsername,
    assetTarget: assetTarget,
  );
}

void main() {
  group('Μορφή χρόνου', () {
    test('δευτερόλεπτα με χιλιοστά', () {
      expect(formatLansweeperElapsed(9384), '9.384 δλ');
      expect(formatLansweeperElapsed(0), '0.000 δλ');
      expect(formatLansweeperElapsed(21412), '21.412 δλ');
    });

    test('αρνητικός χρόνος δεν εμφανίζεται ποτέ', () {
      expect(formatLansweeperElapsed(-5), '0.000 δλ');
    });
  });

  group('Ετικέτες βημάτων', () {
    test(
      'το αίτημα λέει «δημιουργία» ή «ενημέρωση» ανάλογα με την περίπτωση',
      () {
        expect(
          lansweeperSubmitStepLabel(LansweeperSubmitStepKeys.ticket),
          'Δημιουργία αιτήματος',
        );
        expect(
          lansweeperSubmitStepLabel(
            LansweeperSubmitStepKeys.ticket,
            creating: false,
          ),
          'Ενημέρωση αιτήματος',
        );
      },
    );
  });

  group('Πορεία αποστολής', () {
    LansweeperSubmitProgress start() {
      return LansweeperSubmitProgress(
        steps: [
          for (final key in const [
            LansweeperSubmitStepKeys.requester,
            LansweeperSubmitStepKeys.ticket,
            LansweeperSubmitStepKeys.save,
          ])
            LansweeperSubmitStep(
              key: key,
              label: lansweeperSubmitStepLabel(key),
            ),
        ],
        outcome: LansweeperSubmitOutcome.running,
      );
    }

    test('το τρέχον βήμα και η σειρά του', () {
      final progress = start().startStep(LansweeperSubmitStepKeys.ticket, 1200);
      expect(progress.currentStep?.key, LansweeperSubmitStepKeys.ticket);
      expect(progress.currentStepNumber, 2);
      expect(progress.totalSteps, 3);
    });

    test('το προηγούμενο βήμα κλείνει με τον δικό του χρόνο', () {
      final progress = start()
          .startStep(LansweeperSubmitStepKeys.requester, 0)
          .startStep(LansweeperSubmitStepKeys.ticket, 1200)
          .startStep(LansweeperSubmitStepKeys.save, 6000);

      final requester = progress.steps.first;
      final ticket = progress.steps[1];
      expect(requester.status, LansweeperSubmitStepStatus.done);
      expect(requester.elapsedMilliseconds, 1200);
      expect(ticket.status, LansweeperSubmitStepStatus.done);
      // 6000 συνολικά μείον τα 1200 του πρώτου βήματος.
      expect(ticket.elapsedMilliseconds, 4800);
    });

    test('η επιτυχία σφραγίζει συνολικό χρόνο και μήνυμα', () {
      final progress = start()
          .startStep(LansweeperSubmitStepKeys.requester, 0)
          .startStep(LansweeperSubmitStepKeys.save, 5000)
          .finish(
            success: true,
            totalMilliseconds: 8000,
            summary: 'Καταχωρήθηκε · αίτημα 17188',
          );

      expect(progress.outcome, LansweeperSubmitOutcome.success);
      expect(progress.totalMilliseconds, 8000);
      expect(progress.summary, 'Καταχωρήθηκε · αίτημα 17188');
      expect(progress.isRunning, isFalse);
      expect(progress.steps.last.elapsedMilliseconds, 3000);
    });

    test('η αποτυχία σημαδεύει ΜΟΝΟ το βήμα που έτρεχε', () {
      final progress = start()
          .startStep(LansweeperSubmitStepKeys.requester, 0)
          .startStep(LansweeperSubmitStepKeys.ticket, 900)
          .finish(success: false, totalMilliseconds: 4000);

      expect(progress.outcome, LansweeperSubmitOutcome.failure);
      expect(progress.steps.first.status, LansweeperSubmitStepStatus.done);
      expect(progress.steps[1].status, LansweeperSubmitStepStatus.failed);
      // Το βήμα που δεν έφτασε ποτέ να ξεκινήσει μένει εκκρεμές.
      expect(progress.steps.last.status, LansweeperSubmitStepStatus.pending);
    });

    test('βήμα εκτός πλάνου προστίθεται αντί να χαθεί', () {
      final progress = start().startStep('unexpected_step', 100);
      expect(progress.steps.last.key, 'unexpected_step');
      expect(progress.currentStep?.key, 'unexpected_step');
    });
  });

  group('Πλάνο βημάτων', () {
    test('πλήρης αποστολή νέου αιτήματος', () {
      expect(LansweeperSyncService.plannedStepKeys(_request()), const [
        LansweeperSubmitStepKeys.requester,
        LansweeperSubmitStepKeys.ticket,
        LansweeperSubmitStepKeys.note,
        LansweeperSubmitStepKeys.state,
      ]);
    });

    test('χωρίς αιτούντα δεν σχεδιάζεται επαλήθευση', () {
      final keys = LansweeperSyncService.plannedStepKeys(
        _request(requesterUsername: ''),
      );
      expect(keys, isNot(contains(LansweeperSubmitStepKeys.requester)));
    });

    test('χωρίς λύση δεν σχεδιάζεται σημείωση', () {
      final keys = LansweeperSyncService.plannedStepKeys(
        _request(solution: '   '),
      );
      expect(keys, isNot(contains(LansweeperSubmitStepKeys.note)));
    });

    test('ο εξοπλισμός συνδέεται μόνο σε νέο αίτημα', () {
      const asset = LansweeperAssetTarget(
        kind: LansweeperAssetTargetKind.assetName,
        value: 'PC3810',
      );
      expect(
        LansweeperSyncService.plannedStepKeys(_request(assetTarget: asset)),
        contains(LansweeperSubmitStepKeys.asset),
      );
      // Σε υπάρχον αίτημα η ροή δεν περνά καν από τη σύνδεση εξοπλισμού.
      final onExisting = LansweeperSyncService.plannedStepKeys(
        _request(assetTarget: asset, existingTicketId: '17188'),
      );
      expect(onExisting, isNot(contains(LansweeperSubmitStepKeys.asset)));
      expect(onExisting, isNot(contains(LansweeperSubmitStepKeys.ticket)));
    });

    test('χωρίς κατάσταση-στόχο δεν σχεδιάζεται ενημέρωση κατάστασης', () {
      final keys = LansweeperSyncService.plannedStepKeys(
        _request(targetState: ''),
      );
      expect(keys, isNot(contains(LansweeperSubmitStepKeys.state)));
    });
  });
}
