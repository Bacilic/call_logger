import 'package:flutter/material.dart';

import '../../../core/models/app_permission.dart';

/// Η λίστα δικαιωμάτων με τικ, μέσα στην καρτέλα του χρήστη.
///
/// **Αποθηκεύει μόνο τις παρακάμψεις.** Τικ που συμφωνεί με την προεπιλογή του
/// δικαιώματος σβήνει την εγγραφή αντί να τη γράψει — έτσι ένα νέο δικαίωμα σε
/// μελλοντική έκδοση δεν χρειάζεται καμία διόρθωση στα υπάρχοντα προφίλ: όσοι
/// δεν το ρύθμισαν ρητά παίρνουν αυτόματα τη νέα προεπιλογή.
///
/// Δείχνει· δεν αποφασίζει. Την αποθήκευση την κάνει η φόρμα που το φιλοξενεί.
class OperatorPermissionsCard extends StatelessWidget {
  const OperatorPermissionsCard({
    super.key,
    required this.overrides,
    required this.isAdmin,
    required this.onChanged,
    this.readOnly = false,
  });

  /// Μόνο ό,τι έχει οριστεί ρητά. Ό,τι λείπει ακολουθεί την προεπιλογή.
  final Map<String, bool> overrides;

  /// Με σημασμένο διαχειριστή η λίστα δεν ισχύει — η πύλη τον αφήνει να περάσει
  /// χωρίς καν να την κοιτάξει, οπότε δεν επιτρέπουμε τικ που δεν κάνουν τίποτα.
  final bool isAdmin;

  /// Ο **θεατής** δεν είναι διαχειριστής: βλέπει τι ισχύει, δεν αλλάζει τίποτα.
  /// Ξεχωριστό από το [isAdmin], που αφορά τον χρήστη της καρτέλας.
  final bool readOnly;

  final ValueChanged<Map<String, bool>> onChanged;

  bool _isAllowed(AppPermission permission) =>
      overrides[permission.key] ?? permission.allowedByDefault;

  void _toggle(AppPermission permission, bool allowed) {
    final next = Map<String, bool>.from(overrides);
    if (allowed == permission.allowedByDefault) {
      next.remove(permission.key);
    } else {
      next[permission.key] = allowed;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Η σειρά έχει σημασία: το «δεν μπορείτε εσείς» προηγείται του «δεν
        // χρειάζεται γι' αυτόν», γιατί απαντά στο ερώτημα που κάνει ο θεατής.
        if (readOnly)
          _Notice(
            theme: theme,
            icon: Icons.visibility_outlined,
            text:
                'Τα δικαιώματα τα ορίζει μόνο ο διαχειριστής. Εδώ βλέπετε τι '
                'ισχύει, χωρίς να μπορείτε να το αλλάξετε.',
          )
        else if (isAdmin)
          _Notice(
            theme: theme,
            icon: Icons.shield_outlined,
            text:
                'Ο διαχειριστής τα μπορεί όλα και δεν περνά από αυτή τη λίστα. '
                'Για να ρυθμίσετε δικαιώματα, αφαιρέστε πρώτα τη σήμανση '
                '«Διαχειριστής» από την καρτέλα Στοιχεία.',
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              'Ξετικάρετε ό,τι δεν θέλετε να μπορεί να κάνει αυτός ο χρήστης.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final permission in AppPermission.values)
          _PermissionTile(
            permission: permission,
            allowed: _isAllowed(permission),
            enabled: !isAdmin && !readOnly,
            onChanged: (value) => _toggle(permission, value),
          ),
      ],
    );
  }
}

/// Γιατί η λίστα είναι ανενεργή — ο λόγος αλλάζει, η μορφή όχι.
class _Notice extends StatelessWidget {
  const _Notice({required this.theme, required this.icon, required this.text});

  final ThemeData theme;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Μία γραμμή δικαιώματος — με ρητή σήμανση όταν δεν επιβάλλεται ακόμη.
class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.permission,
    required this.allowed,
    required this.enabled,
    required this.onChanged,
  });

  final AppPermission permission;
  final bool allowed;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: allowed,
      onChanged: enabled ? (value) => onChanged(value ?? false) : null,
      title: Row(
        children: [
          Flexible(child: Text(permission.label)),
          if (!permission.enforced) ...[
            const SizedBox(width: 8),
            _NotYetBadge(theme: theme),
          ],
        ],
      ),
      subtitle: Text(
        permission.enforced
            ? _enforcedNote(permission)
            : 'Το τικ αποθηκεύεται, αλλά δεν εμποδίζει τίποτα ακόμη.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static String _enforcedNote(AppPermission permission) {
    return switch (permission) {
      // Δείχνει τους ωμούς πίνακες, άρα και ό,τι έχει κρυφτεί αλλού — μαζί με
      // τα προσωπικά κλειδιά ΤΝ σε απλό κείμενο.
      AppPermission.browseDatabase =>
        'Παρακάμπτει κάθε άλλο δικαίωμα: δείχνει τους πίνακες όπως είναι.',
      _ => 'Ισχύει.',
    };
  }
}

/// Η σήμανση «δηλωμένο αλλά ανενεργό».
class _NotYetBadge extends StatelessWidget {
  const _NotYetBadge({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'δεν ισχύει ακόμη',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
