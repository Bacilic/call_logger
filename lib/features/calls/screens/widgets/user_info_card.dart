import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/equipment_model.dart';
import '../../models/user_model.dart';

/// Κάρτα στοιχείων χρήστη και εξοπλισμού (όνομα, τμήμα, τηλέφωνο, τοποθεσία, εξοπλισμός).
class UserInfoCard extends ConsumerWidget {
  const UserInfoCard({
    super.key,
    required this.user,
    this.equipment,
    this.equipmentCodeText = '',
  });

  final UserModel user;
  final EquipmentModel? equipment;
  final String equipmentCodeText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user.name ?? '—',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _row(theme, Icons.business, 'Τμήμα', user.departmentName ?? '–'),
                      _row(theme, Icons.phone, 'Τηλ.', user.phone),
                    ],
                  ),
                ),
              ],
            ),
            if (equipment != null) ...[
              const Divider(height: 24),
              Text(
                'Εξοπλισμός',
                style: theme.textTheme.titleSmall,
              ),
              _row(theme, Icons.computer, 'Τύπος', equipment!.type),
              _row(theme, Icons.tag, 'Κωδικός εξοπλισμού', equipment!.code),
            ],
          ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$label: ', style: theme.textTheme.bodySmall),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
