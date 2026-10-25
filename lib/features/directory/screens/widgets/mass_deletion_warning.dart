import 'package:flutter/material.dart';

import '../../services/mass_deletion_guard.dart';

/// Η προειδοποίηση μαζικής διαγραφής, κοινή στους διαλόγους υπαλλήλων,
/// τμημάτων και εξοπλισμού.
///
/// - Από το ρυθμισμένο ποσοστό και πάνω: πλαίσιο με «Χ από Υ (Ζ%)».
/// - Ολόκληρος ο κατάλογος: κόκκινο πλαίσιο και πεδίο για τη λέξη
///   [kWholeCatalogConfirmWord]. Το αν ενεργοποιείται το κουμπί το κρίνει ο
///   διάλογος με το [massDeletionConfirmAllowed].
class MassDeletionWarning extends StatelessWidget {
  const MassDeletionWarning({
    super.key,
    required this.massDeletion,
    required this.deleting,
    required this.onTypedWordChanged,
  });

  final MassDeletionContext massDeletion;

  /// Πόσα σβήνονται τώρα — μετά από όσα αφαίρεσε ο χρήστης από τη λίστα.
  final int deleting;
  final ValueChanged<String> onTypedWordChanged;

  @override
  Widget build(BuildContext context) {
    final level = massDeletion.levelFor(deleting);
    if (level == MassDeletionLevel.none) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final whole = level == MassDeletionLevel.whole;
    final background = whole ? scheme.errorContainer : scheme.tertiaryContainer;
    final foreground = whole
        ? scheme.onErrorContainer
        : scheme.onTertiaryContainer;
    final text = whole
        ? massDeletionWholeText(
            catalog: massDeletion.catalog,
            catalogTotal: massDeletion.catalogTotal,
          )
        : massDeletionShareText(
            catalog: massDeletion.catalog,
            deleting: deleting,
            catalogTotal: massDeletion.catalogTotal,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (whole) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('mass-deletion-confirm-word'),
                autofocus: true,
                onChanged: onTypedWordChanged,
                decoration: InputDecoration(
                  labelText:
                      'Γράψτε «$kWholeCatalogConfirmWord» για να '
                      'ενεργοποιηθεί η διαγραφή',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
