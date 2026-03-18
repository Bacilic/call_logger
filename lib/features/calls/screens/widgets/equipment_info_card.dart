import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/equipment_model.dart';

/// Κάρτα στοιχείων εξοπλισμού (τύπος, κωδικός).
class EquipmentInfoCard extends ConsumerWidget {
  const EquipmentInfoCard({
    super.key,
    required this.equipment,
    required this.equipmentCodeText,
  });

  final EquipmentModel? equipment;
  final String equipmentCodeText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final codeDisplay = (equipment?.code != null &&
            equipment!.code!.trim().isNotEmpty)
        ? equipment!.code!.trim()
        : equipmentCodeText.trim();
    final typeDisplay = (equipment?.type != null &&
            equipment!.type!.trim().isNotEmpty)
        ? equipment!.type!.trim()
        : (codeDisplay.isNotEmpty ? '–' : null);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.computer, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Text(
                      'Εξοπλισμός',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (typeDisplay != null)
                _row(theme, Icons.category, 'Τύπος', typeDisplay),
              if (codeDisplay.isNotEmpty)
                _row(theme, Icons.tag, 'Κωδικός εξοπλισμού', codeDisplay),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _row(
    ThemeData theme,
    IconData icon,
    String label,
    String? value,
  ) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$label: ', style: theme.textTheme.bodySmall),
          Flexible(
            fit: FlexFit.loose,
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
