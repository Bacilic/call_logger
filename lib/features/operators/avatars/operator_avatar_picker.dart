import 'package:flutter/material.dart';

import 'operator_avatar_catalog.dart';
import 'operator_avatar_image.dart';

/// Ο επιλογέας εικονιδίου μέσα στην καρτέλα χρήστη.
///
/// **Τα πιασμένα φαίνονται, αλλά δεν πατιούνται.** Η εναλλακτική —να κρύβονται—
/// θα άφηνε τον χρήστη να αναρωτιέται πού πήγε ο γορίλας που είχε δει στη λίστα
/// των συναδέλφων. Έτσι η απάντηση είναι μπροστά του: υπάρχει, τον έχει άλλος,
/// και η υπόδειξη λέει ποιος.
class OperatorAvatarPicker extends StatelessWidget {
  const OperatorAvatarPicker({
    super.key,
    required this.selected,
    required this.takenBy,
    required this.onChanged,
    this.readOnly = false,
  });

  /// Το κλειδί που φοράει τώρα το προφίλ· `null` = κλασικό ανθρωπάκι.
  final String? selected;

  /// Ποιος κρατά κάθε πιασμένο εικονίδιο — κλειδί προς όνομα χρήστη.
  ///
  /// Το εικονίδιο του **ίδιου** του προφίλ που επεξεργάζεται δεν πρέπει να
  /// βρίσκεται εδώ: αλλιώς θα εμφανιζόταν κλειδωμένο από τον εαυτό του.
  final Map<String, String> takenBy;

  final ValueChanged<String?> onChanged;

  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Εικονίδιο', style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          'Ξεχωρίζει τον χρήστη με μια ματιά — στη λίστα, στη μπάρα και στις '
          'εκκρεμότητες. Δύο χρήστες δεν κρατούν το ίδιο.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Tile(
              // Το κλασικό ανθρωπάκι είναι κανονική επιλογή και όχι μόνο
              // εφεδρεία: κάποιος μπορεί να μη θέλει πρόσωπο.
              avatarKey: null,
              label: 'Κλασικό',
              isSelected: findAvatar(selected) == null,
              owner: null,
              onTap: readOnly ? null : () => onChanged(null),
            ),
            for (final avatar in kOperatorAvatars)
              _Tile(
                avatarKey: avatar.key,
                label: avatar.label,
                isSelected: avatar.key == selected,
                owner: takenBy[avatar.key],
                onTap: readOnly || takenBy.containsKey(avatar.key)
                    ? null
                    : () => onChanged(avatar.key),
              ),
          ],
        ),
      ],
    );
  }
}

/// Ένα κελί του επιλογέα.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.avatarKey,
    required this.label,
    required this.isSelected,
    required this.owner,
    required this.onTap,
  });

  final String? avatarKey;
  final String label;
  final bool isSelected;

  /// Ποιος το κρατά· `null` σημαίνει ελεύθερο.
  final String? owner;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taken = owner != null;

    return Tooltip(
      message: taken ? '$label — το κρατά ο/η $owner' : label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isSelected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(3),
          child: OperatorAvatarImage(
            avatarKey: avatarKey,
            size: 42,
            muted: taken,
          ),
        ),
      ),
    );
  }
}
