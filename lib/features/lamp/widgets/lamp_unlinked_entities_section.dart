import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_unlinked_entities.dart';
import '../../../core/widgets/compact_tooltip.dart';

/// Ενότητα «Χωρίς συνδεδεμένο εξοπλισμό», κάτω από τις κάρτες εξοπλισμού.
///
/// **Γιατί χωριστά και όχι ανακατεμένα:** μια αναζήτηση μπορεί να επιστρέψει
/// εκατοντάδες εξοπλισμούς και τρεις ασύνδετες εγγραφές. Ανακατεμένες, οι
/// τρεις χάνονται· μαζεμένες στο τέλος, με το πλήθος τους στον τίτλο,
/// διαβάζονται με μια ματιά και λειτουργούν ως λίστα «προς απόφαση».
class LampUnlinkedEntitiesSection extends StatelessWidget {
  const LampUnlinkedEntitiesSection({
    super.key,
    required this.entities,
    this.onTransfer,
  });

  final List<LampUnlinkedEntity> entities;

  /// Μεταφορά της οντότητας στην κανονική βάση· `null` απενεργοποιεί τα
  /// κουμπιά (π.χ. σε προεπισκόπηση χωρίς ενεργή βάση προορισμού).
  final void Function(LampUnlinkedEntity entity)? onTransfer;

  @override
  Widget build(BuildContext context) {
    if (entities.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 24),
          Row(
            children: [
              Icon(Icons.link_off, size: 18, color: scheme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Χωρίς συνδεδεμένο εξοπλισμό · ${entities.length}',
                  key: const Key('lamp_unlinked_section_title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.tertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Υπάρχουν στη βάση της Λάμπας αλλά δεν τις χρησιμοποιεί κανένας '
            'εξοπλισμός.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final entity in entities)
            _UnlinkedEntityTile(
              key: _tileKey(entity),
              entity: entity,
              onTransfer: onTransfer,
            ),
        ],
      ),
    );
  }

  static Key _tileKey(LampUnlinkedEntity entity) =>
      Key('lamp_unlinked_${entity.kind.name}_${entity.id}');
}

/// Διακριτικό σήμα «κενή εγγραφή» — καμία ένδειξη ότι αντιστοιχεί σε κάτι
/// υπαρκτό (ιδιοκτήτης χωρίς τηλέφωνο/email, γραφείο χωρίς ανθρώπους).
///
/// Πληροφορία, όχι απαγόρευση: η μεταφορά παραμένει διαθέσιμη.
class _EmptyRecordBadge extends StatelessWidget {
  const _EmptyRecordBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CompactTooltip(
      message:
          'Δεν έχει τηλέφωνο, email ή συνδεδεμένους ανθρώπους — πιθανό '
          'κατάλοιπο της παλιάς βάσης. Η μεταφορά παραμένει διαθέσιμη.',
      child: Container(
        key: const Key('lamp_unlinked_empty_badge'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'κενή εγγραφή',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onTertiaryContainer,
          ),
        ),
      ),
    );
  }
}

class _UnlinkedEntityTile extends StatelessWidget {
  const _UnlinkedEntityTile({
    super.key,
    required this.entity,
    this.onTransfer,
  });

  final LampUnlinkedEntity entity;
  final void Function(LampUnlinkedEntity entity)? onTransfer;

  static const Map<LampUnlinkedEntityKind, IconData> _icons =
      <LampUnlinkedEntityKind, IconData>{
        LampUnlinkedEntityKind.office: Icons.account_balance_outlined,
        LampUnlinkedEntityKind.owner: Icons.person_outline,
        LampUnlinkedEntityKind.model: Icons.build_outlined,
        LampUnlinkedEntityKind.contract: Icons.description_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _icons[entity.kind] ?? Icons.help_outline,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: SelectableText.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                // Το είδος και το αναγνωριστικό μαζί: ο χρήστης
                                // συναντά αυτά τα νούμερα στους διαλόγους επίλυσης.
                                text:
                                    '${entity.kind.singularLabel} ${entity.id} · ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              TextSpan(
                                text: entity.title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (entity.isEmptyRecord) ...[
                        const SizedBox(width: 8),
                        const _EmptyRecordBadge(),
                      ],
                    ],
                  ),
                  if (entity.subtitle.isNotEmpty)
                    SelectableText(
                      entity.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // Μοντέλα και συμβάσεις δεν υπάρχουν ως οντότητες στην κανονική
            // βάση — δεν έχουν πού να μεταφερθούν, οπότε ούτε κουμπί.
            if (entity.canTransfer && onTransfer != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: Key('lamp_unlinked_transfer_${entity.kind.name}_${entity.id}'),
                onPressed: () => onTransfer!(entity),
                icon: const Icon(Icons.upgrade, size: 18),
                label: const Text('Μεταφορά'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  // Οι κενές εγγραφές μεταφέρονται κανονικά αν το θελήσει ο
                  // χρήστης — απλώς δεν τραβούν το μάτι σαν πρόταση.
                  foregroundColor: entity.isEmptyRecord
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
