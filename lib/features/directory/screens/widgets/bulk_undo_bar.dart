import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/bulk_action_undo_provider.dart';
import '../../providers/department_directory_provider.dart';
import '../../providers/directory_provider.dart';
import '../../providers/equipment_directory_provider.dart';

/// Μόνιμη μπάρα προσφοράς αναίρεσης μαζικής ενέργειας του καταλόγου.
///
/// Η πράξη έχει ήδη ολοκληρωθεί — η μπάρα μένει ΧΩΡΙΣ χρονόμετρο μέχρι ο
/// χρήστης να πατήσει «Εντάξει»/«Αναίρεση» ή να οριστικοποιηθεί σιωπηλά
/// (νέα μεταβολή καταλόγου, αλλαγή βάσης, έξοδος από την εφαρμογή).
/// Η πλοήγηση παντού είναι ελεύθερη — η μπάρα περιμένει την επιστροφή.
///
/// Εμφανίζεται μόνο στην καρτέλα όπου έγινε η ενέργεια ([scope]).
class BulkUndoBar extends ConsumerWidget {
  const BulkUndoBar({super.key, required this.scope});

  final BulkUndoScope scope;

  Future<void> _undo(WidgetRef ref) async {
    switch (scope) {
      case BulkUndoScope.users:
        await ref.read(directoryProvider.notifier).undoPendingBulkAction();
      case BulkUndoScope.equipment:
        await ref
            .read(equipmentDirectoryProvider.notifier)
            .undoPendingBulkAction();
      case BulkUndoScope.departments:
        await ref
            .read(departmentDirectoryProvider.notifier)
            .undoPendingBulkAction();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(pendingBulkUndoProvider);
    if (offer == null || offer.scope != scope) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.undo, size: 20, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                offer.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _undo(ref),
              child: const Text('Αναίρεση'),
            ),
            const SizedBox(width: 4),
            FilledButton.tonal(
              onPressed: () =>
                  ref.read(pendingBulkUndoProvider.notifier).settleSilently(),
              child: const Text('Εντάξει'),
            ),
          ],
        ),
      ),
    );
  }
}
