import 'package:flutter/material.dart';

import '../models/database_backup_settings.dart';
import 'backup_int_setting_field.dart';

/// «Πολιτική διατήρησης»: χωριστά όρια για γρήγορα και πλήρη αντίγραφα.
class BackupTabRetentionSection extends StatelessWidget {
  const BackupTabRetentionSection({
    super.key,
    required this.settings,
    required this.quickMaxCopiesController,
    required this.quickMaxCopiesFocus,
    required this.onPersistQuickMaxCopies,
    required this.onToggleQuickMaxCopies,
    required this.quickMaxAgeController,
    required this.quickMaxAgeFocus,
    required this.onPersistQuickMaxAge,
    required this.onToggleQuickMaxAge,
    required this.fullMaxCopiesController,
    required this.fullMaxCopiesFocus,
    required this.onPersistFullMaxCopies,
    required this.onToggleFullMaxCopies,
  });

  final DatabaseBackupSettings settings;
  final TextEditingController quickMaxCopiesController;
  final FocusNode quickMaxCopiesFocus;
  final Future<void> Function() onPersistQuickMaxCopies;
  final ValueChanged<bool> onToggleQuickMaxCopies;
  final TextEditingController quickMaxAgeController;
  final FocusNode quickMaxAgeFocus;
  final Future<void> Function() onPersistQuickMaxAge;
  final ValueChanged<bool> onToggleQuickMaxAge;
  final TextEditingController fullMaxCopiesController;
  final FocusNode fullMaxCopiesFocus;
  final Future<void> Function() onPersistFullMaxCopies;
  final ValueChanged<bool> onToggleFullMaxCopies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Πολιτική διατήρησης',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Χωριστά όρια για τα γρήγορα (.db) και τα πλήρη (.zip)· '
          'διαγράφεται πάντα το παλαιότερο όταν ξεπεραστεί το όριο.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        _RetentionRuleRow(
          leadingText: 'Γρήγορα: διατήρηση των τελευταίων ',
          trailingText: ' αντιγράφων',
          controller: quickMaxCopiesController,
          focusNode: quickMaxCopiesFocus,
          onPersist: onPersistQuickMaxCopies,
          enabled: settings.retentionQuickMaxCopiesEnabled,
          onToggle: onToggleQuickMaxCopies,
        ),
        _RetentionRuleRow(
          leadingText: 'Γρήγορα: διαγραφή παλαιότερων από ',
          trailingText: ' ημέρες',
          controller: quickMaxAgeController,
          focusNode: quickMaxAgeFocus,
          onPersist: onPersistQuickMaxAge,
          enabled: settings.retentionQuickMaxAgeEnabled,
          onToggle: onToggleQuickMaxAge,
        ),
        _RetentionRuleRow(
          leadingText: 'Πλήρη: διατήρηση των τελευταίων ',
          trailingText: ' αντιγράφων',
          controller: fullMaxCopiesController,
          focusNode: fullMaxCopiesFocus,
          onPersist: onPersistFullMaxCopies,
          enabled: settings.retentionFullMaxCopiesEnabled,
          onToggle: onToggleFullMaxCopies,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Το πιο πρόσφατο πλήρες αντίγραφο δεν διαγράφεται ποτέ, '
            'ό,τι κι αν λένε τα όρια.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Γραμμή κανόνα διατήρησης: κείμενο, αριθμητικό πεδίο και διακόπτης.
class _RetentionRuleRow extends StatelessWidget {
  const _RetentionRuleRow({
    required this.leadingText,
    required this.trailingText,
    required this.controller,
    required this.focusNode,
    required this.onPersist,
    required this.enabled,
    required this.onToggle,
  });

  final String leadingText;
  final String trailingText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onPersist;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: BackupIntSettingField(
            leadingText: leadingText,
            trailingText: trailingText,
            controller: controller,
            focusNode: focusNode,
            min: 1,
            max: 9999,
            onPersist: onPersist,
          ),
        ),
        Switch(value: enabled, onChanged: onToggle),
      ],
    );
  }
}

/// Τι βλέπει ο χρήστης χωρίς δικαίωμα πλήρους αντιγράφου: ποιος τα χειρίζεται,
/// και πού θα βρει το δικό του αντίγραφο ρυθμίσεων.
class BackupManagedByAdminNotice extends StatelessWidget {
  const BackupManagedByAdminNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Τα αντίγραφα ασφαλείας της βάσης τα χειρίζεται ο '
                    'διαχειριστής.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Το αντίγραφο των δικών σας προσωπικών ρυθμίσεων βρίσκεται στην '
              'καρτέλα «Επαναφορά».',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
