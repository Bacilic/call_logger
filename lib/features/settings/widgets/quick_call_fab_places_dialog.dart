import 'package:flutter/material.dart';

import '../../../core/models/quick_call_fab_places.dart';

/// Υπότιτλος της γραμμής στις Ρυθμίσεις: πόσα σημεία δείχνουν το κουμπί.
String quickCallFabPlacesSubtitle(QuickCallFabPlaces places) {
  final total = QuickCallFabPlace.values.length;
  final n = places.shownCount;
  if (n == total) return 'Φαίνεται σε όλα τα σημεία';
  if (n == 0) return 'Δεν φαίνεται πουθενά· το Ctrl+Shift+N δουλεύει';
  return 'Φαίνεται σε $n από $total σημεία';
}

/// Παράθυρο επιλογής των οθονών όπου φαίνεται το κουμπί γρήγορης κλήσης.
/// Επιστρέφει τη νέα επιλογή στο «Εντάξει», `null` στην «Ακύρωση».
Future<QuickCallFabPlaces?> showQuickCallFabPlacesDialog(
  BuildContext context, {
  required QuickCallFabPlaces initial,
}) {
  return showDialog<QuickCallFabPlaces>(
    context: context,
    builder: (_) => _QuickCallFabPlacesDialog(initial: initial),
  );
}

class _QuickCallFabPlacesDialog extends StatefulWidget {
  const _QuickCallFabPlacesDialog({required this.initial});

  final QuickCallFabPlaces initial;

  @override
  State<_QuickCallFabPlacesDialog> createState() =>
      _QuickCallFabPlacesDialogState();
}

class _QuickCallFabPlacesDialogState extends State<_QuickCallFabPlacesDialog> {
  late QuickCallFabPlaces _places = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Κουμπί γρήγορης κλήσης'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Επιλέξτε σε ποιες οθόνες φαίνεται το κουμπί. Η συντόμευση '
                'Ctrl+Shift+N ανοίγει τη γρήγορη κλήση από παντού.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final place in QuickCallFabPlace.values)
                SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(place.label),
                  value: _places.shows(place),
                  onChanged: (shown) =>
                      setState(() => _places = _places.withPlace(place, shown)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_places),
          child: const Text('Εντάξει'),
        ),
      ],
    );
  }
}
