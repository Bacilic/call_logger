import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lansweeper_sync_state.dart';
import '../providers/lansweeper_settings_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import '../widgets/lansweeper/lansweeper_registration_dialogs.dart';
import '../widgets/lansweeper/lansweeper_registration_flow.dart';
import '../widgets/lansweeper_registration_conflict_dialog.dart';
import 'lansweeper_registration_conflict.dart';

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

  /// Εφαρμόζει τη μετάβαση και επιστρέφει το μήνυμα επιτυχίας.
  ///
  /// Το [currentState] και το [storedTicketId] είναι η κατάσταση **όπως τη
  /// δείχνει η γραμμή μου** — η αφετηρία που κρίνει αν κάποιος πρόλαβε. Χωρίς
  /// αυτήν, μια μετάβαση πάνω σε μπαγιάτικη λίστα σβήνει αθόρυβα το αίτημα που
  /// μόλις καταχώρησε ο συνάδελφος.
  ///
  /// Επιστρέφει `null` όταν ο χρήστης ακύρωσε σε κάποια ερώτηση — ο καλών δεν
  /// ανακοινώνει τίποτα, γιατί τίποτα δεν άλλαξε.
  static Future<String?> apply(
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
        return excluded.isApplied
            ? 'Η κλήση εξαιρέθηκε από το Lansweeper.'
            : null;

      case LansweeperSyncState.unsent:
        final stored = (storedTicketId ?? '').trim();
        if (stored.isEmpty) {
          final cleared = await applyLansweeperChangeWithConflictPrompt(
            context,
            write: ({required force}) =>
                notifier.setUnsent(callId, expected: expected, force: force),
          );
          return cleared.isApplied
              ? 'Η κλήση σημειώθηκε ως ακαταχώρητη.'
              : null;
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
        if (!withdrawn.isApplied) return null;
        return retain
            ? 'Η κλήση σημειώθηκε ως ακαταχώρητη (το αίτημα #$stored διατηρήθηκε).'
            : 'Η κλήση σημειώθηκε ως ακαταχώρητη.';

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

  static Future<String?> _markRegistered(
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
    if (!registered.isApplied) return null;
    return ticketId.isEmpty
        ? 'Η κλήση επισημάνθηκε ως καταχωρημένη.'
        : 'Η κλήση επισημάνθηκε ως καταχωρημένη (αίτημα #$ticketId).';
  }
}
