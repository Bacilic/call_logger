import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/pending_deferred_actions_provider.dart';
import '../services/bulk_action_undo_record.dart';

/// Σε ποια καρτέλα του καταλόγου έγινε η μαζική ενέργεια.
enum BulkUndoScope {
  users('Μαζική ενέργεια υπαλλήλων'),
  equipment('Μαζική ενέργεια εξοπλισμού'),
  departments('Μαζική ενέργεια τμημάτων');

  const BulkUndoScope(this.label);

  final String label;
}

/// Ζωντανή προσφορά αναίρεσης μετά από μαζική ενέργεια του καταλόγου.
///
/// Η πράξη έχει ήδη γραφτεί στη βάση — η προσφορά είναι μόνο η δυνατότητα
/// «άλλαξα γνώμη». Ζει χωρίς χρονόμετρο μέχρι ο χρήστης να αποφασίσει ή να
/// οριστικοποιηθεί σιωπηλά (νέα μεταβολή καταλόγου, αλλαγή βάσης, έξοδος).
class PendingBulkUndoOffer {
  const PendingBulkUndoOffer({
    required this.scope,
    required this.message,
    required this.record,
    required this.deferredToken,
  });

  final BulkUndoScope scope;
  final String message;
  final BulkActionUndoRecord record;

  /// Token στο μητρώο εκκρεμών ενεργειών (οριστικοποίηση πριν από αλλαγή βάσης).
  final int deferredToken;
}

class PendingBulkUndoNotifier extends Notifier<PendingBulkUndoOffer?> {
  @override
  PendingBulkUndoOffer? build() => null;

  /// Δημοσιεύει νέα προσφορά αναίρεσης (οριστικοποιεί σιωπηλά τυχόν παλιά).
  void offer({
    required BulkUndoScope scope,
    required String message,
    required BulkActionUndoRecord record,
  }) {
    settleSilently();
    if (record.isEmpty) return;
    final token = ref
        .read(pendingDeferredActionsProvider.notifier)
        .register(
          label: scope.label,
          settle: () async {
            state = null;
          },
        );
    state = PendingBulkUndoOffer(
      scope: scope,
      message: message,
      record: record,
      deferredToken: token,
    );
  }

  /// Σιωπηλή οριστικοποίηση: η πράξη μένει ως έχει, η προσφορά αποσύρεται.
  void settleSilently() {
    final current = state;
    if (current == null) return;
    ref
        .read(pendingDeferredActionsProvider.notifier)
        .unregister(current.deferredToken);
    state = null;
  }

  /// Αποσύρει την προσφορά και επιστρέφει το πακέτο για εκτέλεση αναίρεσης.
  BulkActionUndoRecord? takeForUndo() {
    final current = state;
    if (current == null) return null;
    ref
        .read(pendingDeferredActionsProvider.notifier)
        .unregister(current.deferredToken);
    state = null;
    return current.record;
  }
}

final pendingBulkUndoProvider =
    NotifierProvider<PendingBulkUndoNotifier, PendingBulkUndoOffer?>(
      PendingBulkUndoNotifier.new,
    );
