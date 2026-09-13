import 'package:flutter/material.dart';

import '../../operators/services/profile_settings_export.dart';

/// «Οι ρυθμίσεις μου»: αντίγραφο και επαναφορά των προσωπικών ρυθμίσεων.
///
/// Ζει δίπλα στην επαναφορά της βάσης, γιατί απαντά στην ίδια ερώτηση του
/// χρήστη — «θέλω τα πράγματά μου πίσω» — και είναι ορατή σε **όλους**: οι
/// προσωπικές ρυθμίσεις είναι του καθενός και δεν θέλουν δικαίωμα.
///
/// Η ενημέρωση γίνεται με κανονικό παράθυρο, όχι snackbar: η ενότητα ζει μέσα
/// στον διάλογο «Ρυθμίσεις βάσης», όπου ένα snackbar θα εμφανιζόταν από πίσω.
class MySettingsBackupSection extends StatelessWidget {
  const MySettingsBackupSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Οι ρυθμίσεις μου',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Οι προσωπικές σας ρυθμίσεις ζουν μέσα στη βάση και έρχονται πίσω '
          'μαζί της. Το ξεχωριστό αντίγραφο χρησιμεύει για να τις πάρετε σε '
          'άλλη βάση ή να τις δώσετε ως αφετηρία σε συνάδελφο.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _export(context),
              icon: const Icon(Icons.save_alt_outlined, size: 18),
              label: const Text('Αντίγραφο των ρυθμίσεών μου'),
            ),
            OutlinedButton.icon(
              onPressed: () => _import(context),
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: const Text('Επαναφορά ρυθμίσεων'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final result = await exportActiveOperatorSettings();
    if (!context.mounted) return;
    if (result.isSaved) {
      await _tell(
        context,
        title: 'Οι ρυθμίσεις αποθηκεύτηκαν',
        message: result.path!,
      );
    } else if (result.error != null) {
      await _tell(
        context,
        title: 'Η αποθήκευση δεν έγινε',
        message: result.error!,
      );
    }
  }

  Future<void> _import(BuildContext context) async {
    final result = await importActiveOperatorSettings();
    if (!context.mounted) return;
    if (result.isRestored) {
      await _tell(
        context,
        title: 'Οι ρυθμίσεις επανήλθαν',
        message:
            'Επανήλθαν ${result.restoredCount} ρυθμίσεις. Κάποιες οθόνες '
            'δείχνουν τις νέες τιμές όταν ξανανοίξουν.',
      );
    } else if (result.error != null) {
      await _tell(
        context,
        title: 'Η επαναφορά δεν έγινε',
        message: result.error!,
      );
    }
  }

  Future<void> _tell(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Εντάξει'),
          ),
        ],
      ),
    );
  }
}
