import 'package:flutter/material.dart';

import '../../services/department_deletion_inventory.dart';

/// Επιλογή μετά την προεπισκόπηση διαγραφής τμήματος.
enum DepartmentDeletionChoice {
  cancel,
  detailed,
  quickAll,
}

/// Προεπισκόπηση «Τι θα συμβεί» πριν τη διαγραφή τμημάτων.
Future<DepartmentDeletionChoice?> showDepartmentDeletionPreviewDialog({
  required BuildContext context,
  required List<DepartmentDeletionInventory> inventories,
}) {
  final hasAnyDependencies = inventories.any((i) => !i.isEmpty);

  return showDialog<DepartmentDeletionChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Τι θα συμβεί'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final inventory in inventories) ...[
                _DepartmentInventoryCard(inventory: inventory),
                const SizedBox(height: 10),
              ],
              if (inventories.any((i) => i.hasEmployees))
                _EmployeesWarningBanner(
                  colorScheme: Theme.of(ctx).colorScheme,
                  textTheme: Theme.of(ctx).textTheme,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(DepartmentDeletionChoice.cancel),
          child: const Text('Ακύρωση'),
        ),
        if (hasAnyDependencies) ...[
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(DepartmentDeletionChoice.detailed),
            child: const Text('Αναλυτικά (ανά οντότητα)'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(DepartmentDeletionChoice.quickAll),
            child: const Text('Μεταφορά όλων σε ένα τμήμα…'),
          ),
        ] else
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(DepartmentDeletionChoice.detailed),
            child: const Text('Διαγραφή'),
          ),
      ],
    ),
  );
}

class _DepartmentInventoryCard extends StatelessWidget {
  const _DepartmentInventoryCard({required this.inventory});

  final DepartmentDeletionInventory inventory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaryLines = inventory.buildSummaryLines();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              inventory.departmentName.trim().isEmpty
                  ? '—'
                  : inventory.departmentName.trim(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            if (inventory.isEmpty)
              Text(
                'Δεν υπάρχουν εξαρτήματα',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              for (final line in summaryLines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(line, style: theme.textTheme.bodyMedium),
                ),
              if (inventory.hasEmployees) ...[
                const SizedBox(height: 6),
                Text(
                  _formatEmployeeNames(inventory.employeeNames),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String _formatEmployeeNames(List<String> names) {
  const maxVisible = 5;
  if (names.length <= maxVisible) {
    return names.join(', ');
  }
  final visible = names.take(maxVisible).join(', ');
  final remaining = names.length - maxVisible;
  return '$visible (+$remaining ακόμη)';
}

class _EmployeesWarningBanner extends StatelessWidget {
  const _EmployeesWarningBanner({
    required this.colorScheme,
    required this.textTheme,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          'Θα σας ζητηθεί πού μεταφέρεται κάθε υπάλληλος πριν διαγραφεί το '
          'τμήμα.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
