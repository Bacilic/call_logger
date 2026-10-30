import 'package:flutter/material.dart';

import '../floor_plan_item_info.dart';

/// Η υπόδειξη με το πέρασμα του ποντικιού πάνω από ένα σύμβολο του χάρτη:
/// λίγες γραμμές, χωρίς κουμπιά.
class FloorPlanItemTooltip extends StatelessWidget {
  const FloorPlanItemTooltip({super.key, required this.info});

  final FloorPlanItemInfo info;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _InfoBody(info: info, withNotes: false),
          ),
        ),
      ),
    );
  }
}

/// Τα πλήρη στοιχεία ενός συμβόλου, με κλικ: ό,τι λέει η υπόδειξη, οι
/// σημειώσεις, και για τις εγγραφές του Καταλόγου «Άνοιγμα καρτέλας».
class FloorPlanItemDetailsPanel extends StatelessWidget {
  const FloorPlanItemDetailsPanel({
    super.key,
    required this.info,
    required this.onClose,
    this.onOpenCard,
    this.footer,
  });

  final FloorPlanItemInfo info;
  final VoidCallback onClose;

  /// `null` όταν η εγγραφή δεν έχει καρτέλα στον Κατάλογο.
  final VoidCallback? onOpenCard;

  /// Κάτω από τα στοιχεία — π.χ. η πρόσοψη με τις θύρες.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Κλείσιμο',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _InfoBody(info: info, withNotes: true),
              ),
              if (footer case final footer?) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: footer,
                ),
              ],
              if (onOpenCard != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: onOpenCard,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Άνοιγμα καρτέλας'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBody extends StatelessWidget {
  const _InfoBody({required this.info, required this.withNotes});

  final FloorPlanItemInfo info;
  final bool withNotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = info.notes?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(info.title, style: theme.textTheme.titleSmall),
        Text(
          info.kindLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        for (final (label, value) in info.rows)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  TextSpan(text: value),
                ],
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (info.warning case final warning?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.orange.shade800,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    warning,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (withNotes && notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Σημειώσεις', style: theme.textTheme.labelMedium),
          Text(notes, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}
