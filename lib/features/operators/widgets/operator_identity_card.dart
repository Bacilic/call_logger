import 'package:flutter/material.dart';

import '../../../core/models/operator.dart';
import '../avatars/operator_avatar_image.dart';
import '../services/operator_presence_summary.dart';

/// Η ταυτότητα ενός χρήστη σε μορφή κάρτας — εικονίδιο, όνομα, ρόλος,
/// λογαριασμός Windows και πότε συνδέθηκε τελευταία φορά.
///
/// **Μία πηγή για δύο πλαίσια:** τη λίστα «Χρήστες» και τον επιλογέα ταυτότητας
/// («Ποιος χρησιμοποιεί την εφαρμογή;» και «Αλλαγή χρήστη»). Όποιος διαλέγει
/// ποιος θα υπογράφει τις ενέργειές του πρέπει να βλέπει τα ίδια στοιχεία με
/// όποιον τα διαχειρίζεται — αλλιώς διαλέγει στα τυφλά ανάμεσα σε ονόματα.
class OperatorIdentityCard extends StatelessWidget {
  const OperatorIdentityCard({
    super.key,
    required this.operator,
    this.presence = const <OperatorPresenceLine>[],
    this.extraTags = const <String>[],
    this.trailing,
    this.onTap,
  });

  final Operator operator;

  /// Έτοιμες γραμμές σύνδεσης — η κάρτα δείχνει, δεν υπολογίζει.
  final List<OperatorPresenceLine> presence;

  /// Σημάνσεις πέρα από τον ρόλο, π.χ. «Εσείς» ή «Απενεργοποιημένος».
  final List<String> extraTags;

  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = !operator.isActive;
    final titleColor = muted ? theme.colorScheme.onSurfaceVariant : null;

    final subtitle = operator.windowsAccount == null
        ? 'Χωρίς λογαριασμό Windows — επιλέγεται χειροκίνητα'
        : operator.windowsAccount!;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        // Το εικονίδιο πατά κατευθείαν στην κάρτα, χωρίς χρωματιστό δίσκο από
        // κάτω: οι φιγούρες είναι σχεδιασμένες να στέκονται μόνες τους, και ο
        // δίσκος θα έκοβε ό,τι ξεπερνά τον κύκλο — καπέλα, φτερά, αυτιά.
        leading: OperatorAvatarImage(
          avatarKey: operator.avatarKey,
          size: 44,
          muted: muted,
        ),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              operator.displayName,
              style: theme.textTheme.titleMedium?.copyWith(color: titleColor),
            ),
            // Ο ρόλος γράφεται πάντα, και για τους δύο. Η απουσία σήμανσης
            // διαβάζεται ως «δεν ξέρω», όχι ως «απλός χρήστης».
            OperatorTag(label: operator.isAdmin ? 'Διαχειριστής' : 'Χρήστης'),
            if (operator.windowsAccount == null)
              const OperatorTag(label: 'Αυτόνομο'),
            for (final tag in extraTags) OperatorTag(label: tag),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (operator.windowsAccount != null) ...[
                  Icon(
                    Icons.badge_outlined,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            for (final line in presence)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      line.online
                          ? Icons.circle
                          : Icons.history_toggle_off_outlined,
                      size: line.online ? 9 : 15,
                      color: line.online
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    SizedBox(width: line.online ? 7 : 4),
                    Flexible(
                      child: Text(
                        line.text,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: line.online
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: trailing,
      ),
    );
  }
}

/// Μικρή σήμανση δίπλα στο όνομα (ρόλος, «Εσείς», «Αυτόνομο», …).
class OperatorTag extends StatelessWidget {
  const OperatorTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
