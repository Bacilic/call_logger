import 'package:flutter/material.dart';

import '../../audit/models/audit_log_model.dart';
import '../../audit/services/audit_formatter_service.dart';

/// Αναδιπλούμενη ενότητα «Πριν / Μετά» από JSON τιμών audit.
class AuditBeforeAfterSection extends StatelessWidget {
  const AuditBeforeAfterSection({
    super.key,
    required this.entry,
    this.formatter = const AuditFormatterService(),
  });

  final AuditLogModel entry;
  final AuditFormatterService formatter;

  @override
  Widget build(BuildContext context) {
    if (!entry.hasAnyDeltaJson) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final hasOld = entry.hasOldJson;
    final hasNew = entry.hasNewJson;
    final changes = formatter.describeChanges(entry);
    final primary = formatter.primaryChangeLine(entry);
    final extraChanges = primary == null
        ? changes
        : changes.where((c) => c != primary).toList();
    return ExpansionTile(
      initiallyExpanded: hasOld || hasNew,
      title: Text(
        'Τι άλλαξε',
        style: theme.textTheme.titleSmall,
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (extraChanges.isNotEmpty)
          ...extraChanges.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: theme.textTheme.bodySmall,
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (extraChanges.isEmpty)
          Text(
            'Δεν υπάρχουν πρόσθετες φιλικές αλλαγές πέρα από τη σύνοψη.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(
            'Τεχνικές λεπτομέρειες (JSON)',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Προηγούμενες τιμές',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasOld
                  ? formatter.prettyJsonBlock(entry.oldValuesJson)
                  : 'Δεν υπάρχει προηγούμενη τιμή.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Νέες τιμές',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasNew
                  ? formatter.prettyJsonBlock(entry.newValuesJson)
                  : 'Δεν υπάρχει νέα τιμή.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
