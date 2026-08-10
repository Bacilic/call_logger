import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lansweeper_sync_state.dart';
import '../providers/lansweeper_settings_provider.dart';
import '../providers/lansweeper_sync_provider.dart';
import '../widgets/lansweeper/lansweeper_registration_dialogs.dart';

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
  /// Επιστρέφει `null` όταν ο χρήστης ακύρωσε σε κάποια ερώτηση — ο καλών δεν
  /// ανακοινώνει τίποτα, γιατί τίποτα δεν άλλαξε.
  static Future<String?> apply(
    BuildContext context,
    WidgetRef ref, {
    required int callId,
    required String? storedTicketId,
    required String targetState,
  }) async {
    final notifier = ref.read(lansweeperSyncProvider.notifier);
    switch (LansweeperSyncState.normalize(targetState)) {
      case LansweeperSyncState.excluded:
        await notifier.setExcluded(callId);
        return 'Η κλήση εξαιρέθηκε από το Lansweeper.';

      case LansweeperSyncState.unsent:
        final stored = (storedTicketId ?? '').trim();
        if (stored.isEmpty) {
          await notifier.setUnsent(callId);
          return 'Η κλήση σημειώθηκε ως ακαταχώρητη.';
        }
        // Το αποθηκευμένο αίτημα μπορεί να υπάρχει πράγματι στο Lansweeper —
        // το σβήσιμό του χωρίς ερώτηση θα έσπαγε τον δεσμό αθόρυβα.
        final choice = await showLansweeperUnsentTicketChoiceDialog(
          context,
          storedTicket: stored,
          ticketViewUrlTemplate: ref.read(lansweeperTicketViewUrlProvider),
        );
        if (choice == null || choice == UnsentTicketChoice.cancel) return null;
        await notifier.setUnsent(
          callId,
          retainTicketId: choice == UnsentTicketChoice.retain,
        );
        return choice == UnsentTicketChoice.retain
            ? 'Η κλήση σημειώθηκε ως ακαταχώρητη (το αίτημα #$stored διατηρήθηκε).'
            : 'Η κλήση σημειώθηκε ως ακαταχώρητη.';

      case LansweeperSyncState.sent:
        return _markRegistered(
          context,
          ref,
          callId: callId,
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
    required String? storedTicketId,
  }) async {
    final notifier = ref.read(lansweeperSyncProvider.notifier);
    var prefilled = (storedTicketId ?? '').trim();
    if (prefilled.isEmpty) {
      prefilled = await notifier.suggestedNextLansweeperTicketId() ?? '';
    }
    while (true) {
      if (!context.mounted) return null;
      final ticketId = await showLansweeperOptionalTicketIdDialog(
        context,
        prefilled: prefilled,
        title: 'Σήμανση ως καταχωρημένη',
        subtitle:
            'Ο αριθμός αιτήματος Lansweeper είναι προαιρετικός (π.χ. 17132).',
      );
      if (ticketId == null || !context.mounted) return null;

      if (ticketId.isNotEmpty) {
        final duplicates = await notifier.countRegisteredCallsWithTicketId(
          ticketId,
          excludeCallId: callId,
        );
        if (!context.mounted) return null;
        if (duplicates > 0) {
          final action = await showLansweeperDuplicateTicketDialog(
            context,
            count: duplicates,
            ticketId: ticketId,
            ticketViewUrlTemplate: ref.read(lansweeperTicketViewUrlProvider),
          );
          if (action == DuplicateTicketAction.cancel || !context.mounted) {
            return null;
          }
          if (action == DuplicateTicketAction.changeId) {
            prefilled = ticketId;
            continue;
          }
        }
      }

      await notifier.markRegistered(
        callId: callId,
        ticketId: ticketId.isEmpty ? null : ticketId,
      );
      return ticketId.isEmpty
          ? 'Η κλήση επισημάνθηκε ως καταχωρημένη.'
          : 'Η κλήση επισημάνθηκε ως καταχωρημένη (αίτημα #$ticketId).';
    }
  }
}
