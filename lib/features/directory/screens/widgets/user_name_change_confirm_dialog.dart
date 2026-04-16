import 'package:flutter/material.dart';

/// Επιλογή μετά από αλλαγή «κλειδιού» ονοματεπώνυμου (επεξεργασία).
enum UserNameChangeDialogChoice {
  /// Ενημέρωση της ίδιας εγγραφής· ιστορικό κλήσεων παραμένει στο ίδιο id.
  sameRecord,

  /// Νέος χρήστης· αντιγραφή συνδέσεων εξοπλισμού· ο παλιός παραμένει στη λίστα.
  newEmployee,
}

/// Διάλογος επιλογής τρόπου αποθήκευσης όταν αλλάζει το κανονικοποιημένο ονοματεπώνυμο.
Future<UserNameChangeDialogChoice?> showUserNameChangeConfirmDialog({
  required BuildContext context,
  required String oldDisplayName,
  required String newDisplayName,
}) {
  return showDialog<UserNameChangeDialogChoice>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _UserNameChangeConfirmDialog(
      oldDisplayName: oldDisplayName,
      newDisplayName: newDisplayName,
    ),
  );
}

class _UserNameChangeConfirmDialog extends StatefulWidget {
  const _UserNameChangeConfirmDialog({
    required this.oldDisplayName,
    required this.newDisplayName,
  });

  final String oldDisplayName;
  final String newDisplayName;

  @override
  State<_UserNameChangeConfirmDialog> createState() =>
      _UserNameChangeConfirmDialogState();
}

class _UserNameChangeConfirmDialogState
    extends State<_UserNameChangeConfirmDialog> {
  UserNameChangeDialogChoice? _choice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final oldL = widget.oldDisplayName.trim().isEmpty ? '—' : widget.oldDisplayName.trim();
    final newL = widget.newDisplayName.trim().isEmpty ? '—' : widget.newDisplayName.trim();

    return AlertDialog(
      title: const Text('Αλλαγή ονοματεπώνυμου'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Αλλάζετε το «$oldL» σε «$newL».',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _NameChangeOptionTile(
              selected: _choice == UserNameChangeDialogChoice.sameRecord,
              title: 'Ενημέρωση της ίδιας εγγραφής',
              subtitle:
                  'Το ιστορικό κλήσεων και οι συνδέσεις εξοπλισμού παραμένουν στην ίδια εγγραφή.',
              onTap: () =>
                  setState(() => _choice = UserNameChangeDialogChoice.sameRecord),
            ),
            const SizedBox(height: 8),
            _NameChangeOptionTile(
              selected: _choice == UserNameChangeDialogChoice.newEmployee,
              title: 'Νέος υπάλληλος',
              subtitle:
                  'Δημιουργείται νέος χρήστης με τα νέα στοιχεία· αντιγράφονται οι συνδέσεις εξοπλισμού.\nΟ παλιός παραμένει ορατός· οι παλιές κλήσεις δεν αλλάζουν Καλών.',
              onTap: () =>
                  setState(() => _choice = UserNameChangeDialogChoice.newEmployee),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: _choice == null
              ? null
              : () => Navigator.of(context).pop(_choice),
          child: const Text('Συνέχεια'),
        ),
      ],
    );
  }
}

class _NameChangeOptionTile extends StatelessWidget {
  const _NameChangeOptionTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 22,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
