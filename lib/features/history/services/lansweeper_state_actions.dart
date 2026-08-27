import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lansweeper_sync_state.dart';
import '../providers/lansweeper_settings_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import '../widgets/lansweeper/lansweeper_registration_dialogs.dart';
import '../widgets/lansweeper/lansweeper_registration_flow.dart';
import '../widgets/lansweeper_registration_conflict_dialog.dart';
import 'lansweeper_registration_conflict.dart';

/// Τι πρέπει να ανακοινωθεί μετά από μια μετάβαση κατάστασης Lansweeper.
///
/// Αντικαθιστά το σκέτο `String?`, όπου το `null` σήμαινε **και** «ακύρωσε ο
/// χρήστης» **και** «απέτυχε η εγγραφή» — με αποτέλεσμα η αποτυχία να περνά
/// τελείως σιωπηλά: η κλήση δεν άλλαζε και καμία λέξη δεν εμφανιζόταν.
class LansweeperStateActionMessage {
  const LansweeperStateActionMessage(this.text, {this.failureReport});

  /// Η πρόταση που βλέπει ο χειριστής.
  final String text;

  /// Η τεχνική αναφορά προς αντιγραφή· `null` όταν δεν πρόκειται για σφάλμα.
  final String? failureReport;

  bool get isFailure => failureReport != null;
}

/// Αλλαγή της κατάστασης Lansweeper μιας κλήσης, με τις ερωτήσεις που χρωστά.
///
/// Οι μεταβάσεις είναι αμφίδρομες: ό,τι εξαιρέθηκε επιστρέφει σε ακαταχώρητη,
/// ό,τι σημάνθηκε καταχωρημένο ξεσημαίνεται. Δεν υπάρχει «κουμπί αναίρεσης»
/// επειδή δεν χρειάζεται — η αντίστροφη κίνηση είναι κανονική μετάβαση.
///
/// Ζει έξω από τα widgets ώστε το Ιστορικό και η Αναφορά να μη γράψουν δύο
/// εκδοχές των ίδιων ερωτήσεων (αποθηκευμένο αίτημα, διπλότυπο id).
abstract final class LansweeperStateActions {
  /// Οι μεταβάσεις που προσφέρονται από μια κλήση σε [currentState].
  ///
  /// Η τρέχουσα κατάσταση λείπει — δεν είναι μετάβαση. Η εξαίρεση λείπει από
  /// τις καταχωρημένες: κλήση που έχει ήδη αίτημα δεν «εξαιρείται», πρώτα
  /// ξεσημαίνεται.
  static List<String> availableTargets(String? currentState) {
    final current = LansweeperSyncState.normalize(currentState);
    return [
      for (final state in const [
        LansweeperSyncState.unsent,
        LansweeperSyncState.excluded,
        LansweeperSyncState.sent,
      ])
        if (state != current &&
            !(state == LansweeperSyncState.excluded &&
                current == LansweeperSyncState.sent))
          state,
    ];
  }

  /// Ετικέτα ενέργειας — τι θα κάνει το πάτημα, όχι πού θα καταλήξει.
  static String actionLabel(String targetState) =>
      switch (LansweeperSyncState.normalize(targetState)) {
        LansweeperSyncState.excluded => 'Εξαίρεση από το Lansweeper',
        LansweeperSyncState.sent => 'Σήμανση ως καταχωρημένη',
        _ => 'Επαναφορά σε ακαταχώρητη',
      };

  /// Εφαρμόζει τη μετάβαση και επιστρέφει το μήνυμα που πρέπει να ειπωθεί.
  ///
  /// Το [currentState] και το [storedTicketId] είναι η κατάσταση **όπως τη
  /// δείχνει η γραμμή μου** — η αφετηρία που κρίνει αν κάποιος πρόλαβε. Χωρίς
  /// αυτήν, μια μετάβαση πάνω σε μπαγιάτικη λίστα σβήνει αθόρυβα το αίτημα που
  /// μόλις καταχώρησε ο συνάδελφος.
  ///
  /// Επιστρέφει `null` **μόνο** όταν ο χρήστης ακύρωσε σε κάποια ερώτηση — τότε
  /// πράγματι δεν υπάρχει τίποτα να ειπωθεί. Η αποτυχία εγγραφής επιστρέφει
  /// μήνυμα, όπως και η επιτυχία: μια αλλαγή που δεν έγινε χωρίς να το πει
  /// κανείς είναι χειρότερη από μια που απέτυχε φωναχτά.
  static Future<LansweeperStateActionMessage?> apply(
    BuildContext context,
    WidgetRef ref, {
    required int callId,
    required String currentState,
    required String? storedTicketId,
    required String targetState,
  }) async {
    final notifier = ref.read(lansweeperSyncProvider.notifier);
    final expected = LansweeperRegistrationBaseline(
      state: currentState,
      ticketId: storedTicketId,
    );
    switch (LansweeperSyncState.normalize(targetState)) {
      case LansweeperSyncState.excluded:
        final excluded = await applyLansweeperChangeWithConflictPrompt(
          context,
          write: ({required force}) =>
              notifier.setExcluded(callId, expected: expected, force: force),
        );
        return announce(excluded, 'Η κλήση εξαιρέθηκε από το Lansweeper.');

      case LansweeperSyncState.unsent:
        final stored = (storedTicketId ?? '').trim();
        if (stored.isEmpty) {
          final cleared = await applyLansweeperChangeWithConflictPrompt(
            context,
            write: ({required force}) =>
                notifier.setUnsent(callId, expected: expected, force: force),
          );
          return announce(cleared, 'Η κλήση σημειώθηκε ως ακαταχώρητη.');
        }
        // Το αποθηκευμένο αίτημα μπορεί να υπάρχει πράγματι στο Lansweeper —
        // το σβήσιμό του χωρίς ερώτηση θα έσπαγε τον δεσμό αθόρυβα.
        final choice = await showLansweeperUnsentTicketChoiceDialog(
          context,
          storedTicket: stored,
          ticketViewUrlTemplate: ref.read(lansweeperTicketViewUrlProvider),
        );
        if (choice == null || choice == UnsentTicketChoice.cancel) return null;
        if (!context.mounted) return null;
        final retain = choice == UnsentTicketChoice.retain;
        final withdrawn = await applyLansweeperChangeWithConflictPrompt(
          context,
          write: ({required force}) => notifier.setUnsent(
            callId,
            expected: expected,
            retainTicketId: retain,
            force: force,
          ),
        );
        return announce(
          withdrawn,
          retain
              ? 'Η κλήση σημειώθηκε ως ακαταχώρητη (το αίτημα #$stored '
                    'διατηρήθηκε).'
              : 'Η κλήση σημειώθηκε ως ακαταχώρητη.',
        );

      case LansweeperSyncState.sent:
        return _markRegistered(
          context,
          ref,
          callId: callId,
          expected: expected,
          storedTicketId: storedTicketId,
        );

      default:
        return null;
    }
  }

  static Future<LansweeperStateActionMessage?> _markRegistered(
    BuildContext context,
    WidgetRef ref, {
    required int callId,
    required LansweeperRegistrationBaseline expected,
    required String? storedTicketId,
  }) async {
    final notifier = ref.read(lansweeperSyncProvider.notifier);
    var prefilled = (storedTicketId ?? '').trim();
    if (prefilled.isEmpty) {
      prefilled = await notifier.suggestedNextLansweeperTicketId() ?? '';
    }
    if (!context.mounted) return null;

    final requested = await showLansweeperOptionalTicketIdDialog(
      context,
      prefilled: prefilled,
      title: 'Σήμανση ως καταχωρημένη',
      subtitle:
          'Ο αριθμός αιτήματος Lansweeper είναι προαιρετικός (π.χ. 17132).',
    );
    if (requested == null || !context.mounted) return null;

    // Ο ίδιος κανόνας διπλού με την Αναφορά — γραμμένος μία φορά, ώστε μια
    // μελλοντική αλλαγή του να μην ξεχαστεί εδώ.
    final ticketId = await resolveTicketIdWithoutDuplicate(
      candidate: requested,
      checkDuplicate: (candidate) async {
        final duplicates = await notifier.countRegisteredCallsWithTicketId(
          candidate,
          excludeCallId: callId,
        );
        if (duplicates <= 0) return DuplicateTicketAction.proceed;
        if (!context.mounted) return DuplicateTicketAction.cancel;
        return showLansweeperDuplicateTicketDialog(
          context,
          count: duplicates,
          ticketId: candidate,
          ticketViewUrlTemplate: ref.read(lansweeperTicketViewUrlProvider),
        );
      },
      askForDifferentId: (currentTicketId) async {
        if (!context.mounted) return null;
        return showLansweeperOptionalTicketIdDialog(
          context,
          prefilled: currentTicketId,
          title: 'Αλλαγή αριθμού αιτήματος',
        );
      },
    );
    if (ticketId == null || !context.mounted) return null;

    final registered = await applyLansweeperChangeWithConflictPrompt(
      context,
      write: ({required force}) => notifier.markRegistered(
        callId: callId,
        expected: expected,
        ticketId: ticketId.isEmpty ? null : ticketId,
        force: force,
      ),
    );
    return announce(
      registered,
      ticketId.isEmpty
          ? 'Η κλήση επισημάνθηκε ως καταχωρημένη.'
          : 'Η κλήση επισημάνθηκε ως καταχωρημένη (αίτημα #$ticketId).',
    );
  }

  /// Μεταφράζει το αποτέλεσμα σε μήνυμα — **το ένα σημείο** που κρίνει πότε το
  /// Ιστορικό μιλά και πότε σιωπά.
  ///
  /// Σιωπή μόνο για την ακύρωση του χρήστη· η αποτυχία λέει την αιτία της, και
  /// όταν δεν την ξέρουμε (έτρεχε ήδη άλλη αποστολή) λέει τουλάχιστον ότι δεν
  /// έγινε.
  @visibleForTesting
  static LansweeperStateActionMessage? announce(
    LansweeperChangeResult result,
    String successText,
  ) {
    switch (result.outcome) {
      case LansweeperChangeOutcome.applied:
        return LansweeperStateActionMessage(successText);
      case LansweeperChangeOutcome.skippedByUser:
        return null;
      case LansweeperChangeOutcome.failed:
        final failure = result.failure;
        return LansweeperStateActionMessage(
          failure == null
              ? 'Η αλλαγή δεν έγινε — υπάρχει ήδη ενεργή αποστολή. Δοκιμάστε '
                    'ξανά σε λίγο.'
              : 'Η αλλαγή δεν έγινε — ${failure.message}',
          failureReport: failure?.report ?? 'Lansweeper change skipped: busy',
        );
    }
  }
}
