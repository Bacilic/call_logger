// Οι ενότητες ενεργειών του διαλόγου αποδέσμευσης: μια πλαισιωμένη λίστα από
// κουμπιά-γραμμές με δική της επικεφαλίδα.
//
// Ξεχωριστή επικεφαλίδα ανά ενότητα ώστε να μη μπερδεύεται το «για αυτό το
// στοιχείο» με το «για όλα».

import 'package:flutter/material.dart';

import '../../../../core/widgets/compact_tooltip.dart';

/// Μία ενέργεια μέσα σε ενότητα ενεργειών.
class AssetDisconnectActionEntry {
  const AssetDisconnectActionEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Καταστροφική ενέργεια — χρωματίζεται με το χρώμα σφάλματος.
  final bool danger;

  /// Υπόδειξη στο hover: τι θα ακολουθήσει αν πατηθεί η ενέργεια — πόσες
  /// ερωτήσεις, σε πόσα στοιχεία, τι αναιρείται. Κενό = χωρίς υπόδειξη.
  final String? tooltip;
}

/// Ενότητα ενεργειών με επικεφαλίδα, πλαίσιο και προαιρετική υποσημείωση.
class AssetDisconnectActionSection extends StatelessWidget {
  const AssetDisconnectActionSection({
    super.key,
    required this.header,
    required this.actions,
    required this.tinted,
    this.footnote,
  });

  final String header;
  final List<AssetDisconnectActionEntry> actions;
  final bool tinted;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = footnote?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(header, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: tinted ? theme.colorScheme.surfaceContainerHighest : null,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++)
                _ActionTile(
                  entry: actions[i],
                  showDivider: i < actions.length - 1,
                ),
            ],
          ),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.entry, required this.showDivider});

  final AssetDisconnectActionEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.danger ? theme.colorScheme.error : null;
    final hint = entry.tooltip?.trim() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              )
            : null,
      ),
      child: _withTooltip(
        hint,
        InkWell(
          onTap: entry.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  entry.icon,
                  size: 18,
                  color: color ?? theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Τυλίγει σε [CompactTooltip] μόνο όταν υπάρχει κείμενο — κενή υπόδειξη θα
  /// άφηνε ένα αόρατο πλαίσιο να κλέβει το hover.
  Widget _withTooltip(String hint, Widget child) {
    if (hint.isEmpty) return child;
    return CompactTooltip(
      message: hint,
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 10),
      child: child,
    );
  }
}
